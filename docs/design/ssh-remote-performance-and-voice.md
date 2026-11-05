# SSH 远程界面性能审查与语音模型解耦

> 2026-11-04，本地审查；基线 `fix/windows-ssh-attach` / `2590a44`，对应已安装的 DSH Go 1.0.10 SSH 测试包。本文件记录现状、证据和建议，**不是已经完成的修复**。
>
> 用户实测：SSH 连接 Windows，旧会话的智能体团队约 3–4 人；打开「消息」后转圈、卡顿并最终卡死。同一会话的普通聊天正常。本次没有连接手机或 Windows 获取性能日志，因此不能仅凭代码确定唯一根因。

## 1. 结论与范围

团队消息和此前 SSH 聊天的性能问题属于同一类：远程一次取得的数据量、解析工作、页面创建的组件数、请求生命周期，需要分别有界。它们发生在不同层，不能只靠一个开关解决。

本次检查了团队、普通聊天、会话列表与搜索、会话控制流、目录与工作区文件、会话产物、任务和插件列表，以及 Bot 聊天的主要路径。表中「结构确认」指代码可确认行为；是否在真实设备上造成卡顿仍需测量，不代表已确认同样的死机。

语音方面，DeepSeek Harness 本身带语音套件。**增加独立的 Android 识别通路，可以保留 DSH 压缩运行环境和官方插件原样；若要从压缩包中删除原语音套件，则是另一项对打包链和原有功能有影响的工作。**

## 2. 之前 SSH 修复与团队页的关系

| 层 | 之前 SSH 聊天已有的处理 | 团队消息页当前行为 | 后续方向 |
|---|---|---|---|
| 连接 | 允许复用现有 Windows/macOS/Linux DSH，通过已验证主机密钥的 SSH 隧道连接；不保存启动令牌 | 使用同一活动连接 | 保留现有信任、鉴权、主机隔离和重连规则 |
| 首次历史 | SSH `turnWindow(10, 1)`、`maxMessages: 50` | 每名成员 `turnWindow: null`、`maxMessages: 200` | 小窗口按成员读取，记录每人游标与 `hasMore`，支持继续加载 |
| 历史翻页 | 普通聊天向前分页，SSH 每页最多请求 50 条消息 | 一次读取后筛选，不保存每人的翻页信息 | 按需读取旧页，不能把缩小首屏窗口误当完整历史 |
| 快照解析 | SSH 聊天启用 `backgroundSnapshotParsing`；目前仅记录数达到 100 时在 worker 解析事件模型 | 没有开启这一选项 | 将相同策略用于团队只读快照，并测量少量超大记录的情况 |
| Mux JSON | SSH 对长度达到 64×1024 的字符串帧在 worker 解码；暂停后续帧以保持顺序 | 团队快照也经过该 Mux 保护，但后续事件模型解析仍在主 isolate | 保留帧顺序，限制 worker 和内存，不把所有帧无条件并行处理 |
| 列表读取 | SSH 对会话、模型、提供方、插件等**固定接口**启用受限后台读取（需符合标准 HTTP carrier 和连接能力条件） | 团队 follow、历史页和许多其他 RPC 不在该白名单 | 按接口扩展；不可假定 `backgroundLists` 覆盖所有远程操作 |
| UI | 普通聊天使用 `SliverChildBuilderDelegate` 按需创建行 | 团队消息把全部结果装进一个 `Column` / `ListPageCard` | 复用已有惰性卡片列表样式，按可见范围创建行 |

依据：[SSH 客户端选项](../../app/lib/remote/ssh/ssh_link.dart#L35)、[聊天首屏](../../app/lib/state/chat_state.dart#L738)、[聊天翻页](../../app/lib/state/chat_state.dart#L1800)、[Mux 解码](../../packages/dsh_client/lib/src/carrier.dart#L228)、[快照解析](../../packages/dsh_client/lib/src/session_api.dart#L1211)、[聊天列表](../../app/lib/ui/chat/chat_list.dart#L574)、[后台接口白名单](../../packages/dsh_client/lib/src/background_session_read.dart#L23)。既有提交记录包括 `790d751`（缩小 SSH 历史同步工作量）和 `6eaabf9`（worker 捕获及翻页测试）；`9548b05` 是复用已有 Windows DSH 的连接能力。部分旧 Git 对象未在本地，未联网补取，故具体行为以当前代码为准。

需要注意：`maxMessages` 是消息窗口请求上限，**不是字节上限**；工具输出或单条消息仍可能很大。后台列表读取目前已有单连接所有者和共享资源调度，包含活动/等待数及响应体约束，不能无视这些保护另造一套无限并行的 worker。[现有调度器](../../packages/dsh_client/lib/src/background_session_read.dart#L65)

## 3. 团队消息：已确认行为和拟修复

### 当前链路

1. [`teamMessagesProvider`](../../app/lib/state/agents_state.dart#L443) 对团队每名成员并发发起一次 follow 快照，最多请求该成员 200 条消息，再遍历事件筛选团队消息。成员活动变化会触发重新读取。
2. `Future.wait` 等所有成员结束；单人未返回时其他结果也不显示。单次读取有 20 秒超时；页面切走时没有将每个正在等待的 follow 随 provider 一起立即取消。
3. [`_MessagesTab`](../../app/lib/ui/agents/team_page.dart#L559) 将全部结果放入同一 `ListPageCard`。文字只显示四行不等于网络载荷或内存中的正文被截短。
4. 用户的 3–4 人规模对应最多请求约 600–800 条**会话消息窗口**，并非 600–800 条团队消息，也不是实际收到的记录数或字节数。事件数量和单条大小仍要实测。

本地模拟已验证：一个成员迟迟不返回时，另外两人的结果也不显示；切走再切回时，三人团队出现六条未完成读取；三人各 200 条团队消息时页面一次创建 600 行。模拟数据不是用户的 Windows 日志，也不能直接代表手机帧率或内存。

### 建议分层处理

1. **数据与生命周期**：使用小的首屏窗口；限制同时读取的成员数；切页、换主机、换团队、刷新时主动取消可取消的旧订阅，迟到结果用连接代次和请求所有者隔离。成员活动更新应合并，条件允许时只更新受影响成员，而不是频繁整队重读。
2. **渐进状态**：某一成员完成即可显示其结果；其他成员保持「读取中」，失败的成员明确提示并可重试。保留已有数据与失败区别，不把超时、部分读取误报为「没有消息」。
3. **历史与正确性**：保留每人 `cursor`、`hasMore`、读取状态；用 `(接收者 sessionId, seq)` 去重，逐批合并，按时间及稳定的次序键排序。尚未读完的成员要标识为部分结果；筛选不到团队消息时，不能宣称全部历史为空。每次自动扫描的页数应有限，继续向前由明确的加载操作触发。
4. **解析与渲染**：复用现有 SSH 快照后台解析；用惰性 sliver 创建消息行，只为可见区域生成组件。评估针对超长消息的预览和完整详情，保留正文，不静默截断或丢失历史。
5. **验证**：覆盖 3–4 个成员、长正文与大量工具事件、慢/失败成员、快速切换、主机切换、重连、活动刷新、空结果但仍有旧页、排序和去重。确认没有重复订阅、并发受限、页面仍可操作；再以手机真机和真实 SSH 大会话记录首屏时间、帧耗时、峰值内存及每个快照的记录数和字节数，不收集消息正文或凭据。

## 4. 其他远程页面和共享路径

| 优先级 / 状态 | 页面或路径 | 已确认的结构与边界 | 建议 |
|---|---|---|---|
| 高；结构确认，需测量 | **共享 `session/control`** | 聊天用量、会话详情面板和团队各自调用 `watchSessionControl()`；每次调用会打开独立的 mux 流，基线包含所有驻留会话的 projections。两个监听在本地模拟中确实打开两条流，是否造成真机卡顿未测量。见 [客户端](../../packages/dsh_client/lib/src/session_api.dart#L872)、[聊天用量](../../app/lib/state/usage_state.dart#L144)、[团队](../../app/lib/state/agents_state.dart#L287)。 | 先量流数、基线大小、解码耗时。若收益明确，按连接/代次共享一条订阅并缓存当前基线供后到者使用；普通广播会让后订阅者漏基线。保留 cold session 的查询兜底、重连换代、顺序、错误和主机隔离。 |
| 高；结构确认，需测量 | **聊天断线后补缺口 / 旧历史** | 普通 SSH 翻页虽请求 50 条，但 [`history()`](../../packages/dsh_client/lib/src/session_api.dart#L603) 的普通 RPC 响应和事件转换仍在主 isolate；[`_fill`](../../packages/dsh_client/lib/src/session_api.dart#L1278) 补缺口每页请求 500，并累积结果。大断档或超大单条记录仍可能产生负担。 | 为 history 和补缺口统一审查页大小、字节量、后台解析及取消；必须保留完整、连续的事件及控制基线，不得为了快静默跳过缺口。 |
| 高；结构确认，需测量 | **远程目录选择器** | Host 每层默认最多返回 1,000 个目录，页面一次创建当前层所有行；有截断提示，也用 `_busy` 防止同时打开多个目录。[API](../../packages/dsh_client/lib/src/workspaces_api.dart#L46) · [UI](../../app/lib/ui/workspace/directory_picker.dart#L430) | 使用项目已有的惰性卡片 sliver，保留隐藏目录、面包屑、截断提示与滚动体验。大响应解析的实际成本先测量。 |
| 中；结构确认，需测量 | **会话搜索 / 归档** | 主机内容搜索最多返回 20 条，且有 250 ms 防抖与过期结果隔离；本地标题/文件夹匹配可覆盖全部会话，结果页用 `ListView(children: ...)` 提前构造所有行。超时或新查询不会自动取消已发出的 Future。[搜索计算](../../app/lib/state/session_search.dart#L164) · [结果页](../../app/lib/ui/shell/session_search_page.dart#L335) | 结果列表按需创建；大历史时测量本地筛选。远程搜索增加可取消或受控并发，并保留旧结果隔离、主机能力与超时提示。 |
| 中；结构确认，需测量 | **团队任务、定时任务、后台任务、已安装插件** | 多个页面在卡片内一次创建所有成员/任务/插件行；`schedule/catalog` 读取主机完整目录，`job/list` 每次变化提供当前全集。常见数据量可能小，不能据此断言这些页面已经卡死。[团队任务](../../app/lib/ui/agents/team_page.dart#L390) · [定时任务](../../app/lib/ui/features/schedules_page.dart#L81) · [任务流](../../app/lib/state/features_state.dart#L47) · [插件](../../app/lib/ui/plugins/installed_tab.dart#L73) | 先按真实数量和刷新频率排序，复用惰性列表组件；对大响应逐接口评估后台解析、去重与增量更新。不要不加判断地重写每个小列表。 |
| 中；结构确认，需测量 | **会话产物完整列表** | 按组的外层 sliver 不是整页简单 `Column`，但每个可见组的 `ListPageCard` 一次创建该组所有文件；数据来自已加载的聊天状态。[实现](../../app/lib/ui/session/session_artifacts.dart#L99) | 测量单轮产物很多的情况，必要时让组内行也惰性创建；不要把它误认为独立拉取完整 SSH 日志。 |
| 已有保护；仍有数据规模风险 | **会话抽屉** | SSH 的会话列表通过固定后台读取处理，抽屉使用 `ListView.builder`；但主机 `session/list` 没有分页，仍会接收全部会话并在手机过滤排序。[读取](../../app/lib/state/sessions_state.dart#L267) · [列表](../../app/lib/ui/shell/drawer/drawer_list.dart#L160) | 保留现有后台调度和增量事件；记录大响应及主线程排序成本。服务端分页能力未核实，不应假定已有。 |
| 已有保护；仍需观察 | **工作区文件列表** | 列表 UI 已有 [`WorkspaceCardSliver`](../../app/lib/ui/files/workspace_browser.dart#L396) 惰性行；文件目录主机默认最多 2,000 项，有截断标记。目录列表仍通过普通 RPC 解析并排序；文件时间最多 120 个、每批 6 个，刷新已有合并和防抖。[状态](../../app/lib/state/workspace_state.dart#L240) | 复用其惰性卡片做团队和目录页面；测量大目录解析、排序及元数据请求，不把现有保护误写成完全无风险。 |
| 已有保护；仍需观察 | **Bot / 群聊** | `chat` / `room-chat` 有游标，UI 使用 `ListView.builder`；部分刷新合并并防重入。[状态](../../app/lib/state/bots_state.dart#L700) · [UI](../../app/lib/ui/bots/bot_chat_kit.dart#L413) | 测长正文和反复翻页的内存；当前证据不足以说它有团队消息页相同缺陷。 |

## 5. 统一修复原则

- **网络层、解析层、UI 层分开治理**：小窗口及服务端分页减少传输；后台解析减少主线程工作；惰性列表减少已创建组件；取消、去重和限流控制请求数量。任一层单独做好都不能代替其他层。
- **复用现成机制**：已有 `WorkspaceCardSliver`、SSH 聊天历史窗口与游标、背景列表资源调度、连接代次/所有者检查。评估可否提炼小型共用能力，而不是每个页面复制一套；也不要把所有 RPC 塞进不支持其语义的现有白名单。
- **语义优先**：全量基线晚到、断线重连、历史缺口、成员延迟、部分失败、主机切换和旧会话翻页都不能导致错主机、错顺序、漏消息、误显示空列表或重复执行控制动作。共享流须向后加入的订阅者提供当前基线。
- **分级交付**：先修团队实际卡死路径并补针对性回归；其次测量共享 control、补缺口和大目录/搜索，基于数据扩大到共用层；低频小列表按实际负载决定。当前只是方案，不把未经真机确认的风险写成已修复。

## 6. 语音模型解耦与运行时兼容

### 原套件来自哪里

实际 APK 的运行时清单是 DSH `0.2.1-rc.4`。项目锁文件中 `@deepseek-ai/dsh` 依赖 `@deepseek-ai/dsh-experimental-voice-input-bundle`，bundle 再依赖 DeepSeek 的 speech API 和 SenseVoice provider，后者依赖 `sherpa-onnx-node`。这支持「复用 DeepSeek Harness 套件」的判断。[锁文件](../../runtime/locks/dsh-0.2.1-rc.4/package-lock.json#L504)

DSH Go 自己负责 Android 录音、设置和模型下载管理；本机引擎使用 [SpeechGuest 覆盖配置](../../app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/runtime/SpeechGuest.kt#L17)。当前 fork 将远程聊天的语音识别路由到手机本地 DSH，而不是 Windows。[路由](../../app/lib/ui/chat/chat_screen.dart#L251)

已检查的 APK 内有 `assets/runtime/rootfs-arm64-v8a.tar.xz`，压缩包为 158,257,168 B（约 158 MB / 151 MiB），清单的解压内容约 786 MB。归档内确有 DeepSeek SenseVoice 的模型清单和 `sherpa-onnx-linux-arm64/sherpa-onnx.node`；提取该文件只作类型检查，结果为 GNU/Linux ARM64 的 Node 原生模块。模型文件是另行下载的 INT8、tokens 与 VAD，清单合计 241,357,257 B（约 241 MB）。[模型路径](../../app/lib/voice/voice_model_assets.dart#L18)

### 哪些变更会影响压缩运行环境

| 方案 | 是否动现有 DSH 压缩运行环境 | 对远程用户的效果和代价 |
|---|---|---|
| 保持现状，改清楚设置说明 | 不动 | 系统识别可不启动本机 DSH；现有 SenseVoice 模型仍需要本机运行环境和引擎。 |
| **新增独立 Android 模型识别，与原 DSH 套件并存** | **不必改动、删除或重打现有 rootfs 内容**；但 App 本身需要新增实现和依赖，日后仍需构建新的 APK | 可在不解压/启动本机 DSH 的情况下下载模型并本机识别；当前 APK 仍携带原 rootfs 压缩包。要另行验证 Android 原生库、ABI、许可证和模型兼容；新增库可能增大 APK，本地 DSH 模式与独立模式还可能各存一份模型。 |
| 仅让模型文件不依赖引擎即可下载 | 不必修改原套件，但需自带可校验的模型清单和独立存放位置 | 可提前下载，却仍不能在没有推理服务时识别，不满足完整的远程仅模型需求。 |
| 从 rootfs 中裁掉原语音 bundle / 原生库 | **会改运行时打包及产物**，并需核对锁文件、依赖、原功能、启动和校验 | 可能减小 rootfs，但可能破坏本机 DSH 的官方语音能力，增加对 DeepSeek 版本变化的维护负担；不是实现独立识别的前提。 |

现有文件是 Linux/Node addon，不能把它当作已验证可在 Android App 中直接调用的 JNI 库；独立 Android 方案需要可用的 Android 原生推理库和适配。建议先保留官方引擎路径，独立路径作为可选能力，验证好版本、模型哈希、资源和生命周期之后再考虑是否迁移/共享已有模型；绝不直接删除用户已安装的模型。录音默认保持在手机，用户发送识别文字后文字仍会按当前远程聊天路径发送。

原作者是否愿意采用属于产品和维护判断，不能仅凭源码断言。仓库当前明确**不接受外部 PR**，建议先用 issue 说明远程用户场景、复现和方案；未收到明确要求，本次不创建 issue 或 PR。[贡献说明](../../CONTRIBUTING.md)

## 7. 本地验证与未验证项

- 上轮：团队消息、语音路由、模型状态等现有测试 47 项通过；另做 3 项三成员临时模拟，验证等待、切换后的未结束读取和 600 行创建，临时文件已删除。
- 本轮：Flutter 既有 SSH 历史、抽屉和搜索测试 **26 项通过、5 项跳过**；跳过的是需要 `DSH_LIVE_URL` / `DSH_LIVE_CWD` 的真实工作区测试。客户端大快照与后台列表测试 **19 项通过**；临时 `session/control` 双订阅模拟 **1 项通过**，临时文件已删除。
- 测试使用本地 fake host / 桌面 Flutter 测试环境；没有真实 Android 设备、真实 SSH/Windows 大历史、实际内存/帧耗时、独立语音 JNI 或上游作者反馈。无法据此保证所有远程页面无卡顿，也不能把模拟耗时当成手机性能。
- 本轮仅新增本文档；没有修改功能代码、推送 GitHub 或构建 APK。

本轮实际执行的常规测试（使用工作区缓存和 Flutter SDK；无 `pub get`、APK 构建或 GitHub 操作）：

```sh
cd app
flutter test --no-pub --reporter expanded \
  test/chat/history_operation_owner_test.dart \
  test/drawer/drawer_list_lazy_test.dart \
  test/search/session_search_widget_test.dart \
  test/files/workspace_live_test.dart

cd ../packages/dsh_client
dart test -r expanded \
  test/ssh_large_snapshot_test.dart \
  test/background_list_read_test.dart
```
