// The model sheet: source filters, model rows, and the capsule effort selector.
// Behaviour, geometry (insets, stacked rows, one dismissal handle) and goldens
// (light + dark). Regenerate with
// `flutter test --update-goldens test/chat/model_sheet_test.dart`.

import 'package:dsh_app/state/chat_state.dart';
import 'package:dsh_app/state/models_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/chat/chat_screen.dart';
import 'package:dsh_app/ui/chat/empty_state.dart';
import 'package:dsh_app/ui/chat/model_sheet.dart';
import 'package:dsh_app/ui/chat/widgets/whale_tail.dart';
import 'package:dsh_app/ui/common/app_sheet.dart';
import 'package:dsh_app/ui/common/segmented_pill.dart';
import 'package:dsh_app/ui/common/sheet_title_bar.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _off = ReasoningEffort('off', 'Off', null);
const _high = ReasoningEffort('high', 'High', null);

/// DeepSeek (two models with efforts) + OpenRouter (one without efforts).
final multiCatalog = ModelCatalog(
  defaultSelection: testCatalog.defaultSelection,
  routableProviders: const ['deepseek-official', 'openrouter'],
  groups: [
    ...testCatalog.groups,
    const ProviderGroup('openrouter', 'OpenRouter', [
      ModelInfo(provider: 'openrouter', id: 'moonshotai/kimi-k2', name: 'Kimi-K2', description: '长上下文，擅长写代码'),
      ModelInfo(
        provider: 'openrouter',
        id: 'z-ai/glm-4.6',
        name: 'GLM-4.6',
        description: '智谱的通用模型',
        efforts: [_off, _high],
        defaultEffort: 'high',
      ),
      ModelInfo(provider: 'openrouter', id: 'qwen/qwen3-coder', name: 'Qwen3-Coder', description: '阿里的代码模型'),
    ]),
  ],
  failures: const [],
);

const _low = ReasoningEffort('low', 'Low', null);
const _medium = ReasoningEffort('medium', 'Medium', null);
const _max = ReasoningEffort('max', 'Max', null);

/// DeepSeek + a custom provider whose models think but name no default
/// effort (what the pi-ai adapter lists for a hand-declared model).
final customCatalog = ModelCatalog(
  defaultSelection: testCatalog.defaultSelection,
  routableProviders: const ['deepseek-official', 'custom-mygw'],
  groups: [
    ...testCatalog.groups,
    const ProviderGroup('custom-mygw', 'My Gateway', [
      ModelInfo(provider: 'custom-mygw', id: 'qwen3-coder', name: 'Qwen3 Coder', efforts: [_off, _low, _medium, _high]),
      ModelInfo(provider: 'custom-mygw', id: 'glm-4.6', name: 'GLM 4.6', efforts: [_off, _high, _max]),
    ]),
  ],
  failures: const [],
);

/// More channels than one capsule row holds.
final crowdedCatalog = ModelCatalog(
  defaultSelection: testCatalog.defaultSelection,
  routableProviders: const [],
  groups: [
    ...multiCatalog.groups,
    for (final (id, name) in const [('siliconflow', 'SiliconFlow'), ('volcengine', '火山引擎方舟'), ('aliyun', '阿里云百炼')])
      ProviderGroup(id, name, [ModelInfo(provider: id, id: '$id-ds', name: 'DeepSeek-V4-Pro')]),
  ],
  failures: const [],
);

/// A third-party channel whose long names the user saw cut ("GPT 5.6 ···").
/// The name lane is only ~109 dp on a 390 dp phone: 16 on one line does not fit.
const longNameCatalog = ModelCatalog(
  defaultSelection: ModelSelection(provider: 'chatgpt', model: 'gpt-6-astra-pro'),
  routableProviders: ['chatgpt'],
  groups: [
    ProviderGroup('chatgpt', 'ChatGPT', [
      ModelInfo(provider: 'chatgpt', id: 'gpt-5.6-terra', name: 'GPT-5.6 Terra', description: '长上下文，擅长复杂推理'),
      ModelInfo(provider: 'chatgpt', id: 'gpt-6-astra', name: 'GPT-6 Astra', description: '新一代旗舰'),
      ModelInfo(provider: 'chatgpt', id: 'gpt-5.6-mini', name: 'GPT-5.6 Mini', description: '轻量快速'),
      ModelInfo(provider: 'chatgpt', id: 'gpt-6-astra-pro', name: 'GPT-6 Astra Pro', description: '代理与工具调用'),
    ]),
  ],
  failures: [],
);

ChatHarness _harness(ModelCatalog catalog, {ModelSelection? model}) => ChatHarness(
  session: model == null ? null : 's1',
  states: {if (model != null) 's1': ChatState(loading: false, model: model)},
  catalog: catalog,
);

Future<ChatHarness> _openSheet(
  WidgetTester tester,
  ChatHarness harness, {
  Brightness brightness = Brightness.light,
}) async {
  usePhoneView(tester);
  mockClipboard(tester);
  await tester.pumpWidget(testApp(const ChatScreen(), brightness: brightness, overrides: harness.overrides));
  await pumpFrames(tester, 6);
  await tester.tap(find.byType(ModelChip));
  await pumpFrames(tester, 8);
  return harness;
}

/// Opens the sheet from a bare page, so a large-text test measures the sheet
/// itself rather than the chat shell behind it.
Future<void> _openSheetAlone(WidgetTester tester, ModelCatalog catalog, {double textScale = 1}) async {
  usePhoneView(tester);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  mockClipboard(tester);
  await tester.pumpWidget(
    testApp(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showModelSheet(context, current: catalog.defaultSelection, onSelected: (_) {}),
              child: const Text('打开模型'),
            ),
          ),
        ),
      ),
      overrides: _harness(catalog).overrides,
    ),
  );
  await pumpFrames(tester, 4);
  await tester.tap(find.text('打开模型'));
  await pumpFrames(tester, 8);
}

Finder _row(String name) => find.ancestor(of: find.text(name), matching: find.byType(Material)).first;

Finder _category(String name) =>
    find.descendant(of: find.byKey(const ValueKey('model-categories')), matching: find.text(name));

ModelSelection? _picked(WidgetTester tester, ChatHarness harness) {
  final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
  return harness.session == null ? container.read(pendingModelProvider) : harness.controllers['s1']!.models.lastOrNull;
}

void main() {
  setUpAll(() async {
    await loadTestFonts();
    await WhaleSprites.load();
    chatClock = () => DateTime(2026, 10, 23, 15, 20);
  });

  testWidgets('narrow model chip keeps complete actionable speech', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    // A long title: the chip gives up its depth before the title is cut.
    final harness = ChatHarness(
      session: 's1',
      states: {'s1': const ChatState(loading: false, title: '修复登录页重复提交并补上连点测试')},
    );
    await tester.pumpWidget(testApp(const ChatScreen(), overrides: harness.overrides));
    await pumpFrames(tester);
    expect(find.text('V4 Pro'), findsOneWidget);
    expect(find.text('V4 Pro · 高'), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('模型：V4 Pro，思考深度高')),
      isSemantics(isButton: true, hasTapAction: true),
    );
    semantics.dispose();
  });

  test('starting effort: the model\'s default, else 中, else the lowest that thinks', () {
    ModelInfo model(List<ReasoningEffort> efforts, {String? defaultEffort}) =>
        ModelInfo(provider: 'p', id: 'm', name: 'M', efforts: efforts, defaultEffort: defaultEffort);
    expect(startingEffort(model(const [])), isNull);
    expect(startingEffort(model(const [_off, _low, _high, _max], defaultEffort: 'high')), 'high');
    expect(startingEffort(model(const [_off, _low, _medium, _high])), 'medium');
    expect(startingEffort(model(const [_off, _high, _max])), 'high');
    expect(startingEffort(model(const [_low, _high])), 'low');
    expect(startingEffort(model(const [_off])), 'off');
    expect(
      startingEffort(model(const [_off, _medium], defaultEffort: 'max')),
      'medium',
      reason: 'a default the model does not list is ignored',
    );
  });

  test('short names drop the DeepSeek prefix', () {
    expect(shortModelName('DeepSeek-V4-Pro'), 'V4 Pro');
    expect(shortModelName('deepseek_v41_flash'), 'V41 Flash');
    expect(shortModelName('GLM-4.6'), 'GLM 4.6');
    expect(shortModelName('DeepSeek'), 'DeepSeek');
  });

  group('behaviour', () {
    testWidgets('one channel: searchable grouped rows and efforts', (tester) async {
      await _openSheet(tester, _harness(testCatalog));
      expect(find.text('选择模型'), findsOneWidget);
      expect(_category('DeepSeek'), findsOneWidget);
      expect(find.byKey(const ValueKey('model-search')), findsOneWidget);
      expect(find.text('V4 Pro'), findsOneWidget);
      expect(find.text('V41 Flash'), findsOneWidget);
      expect(find.text('思考深度'), findsOneWidget);
      // Only the effort selector is a segmented pill.
      expect(find.byType(SegmentedPill<String>), findsOneWidget);
      for (final label in ['不思考', '低', '高', '最高']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('source filters only the list and keeps the current selection', (tester) async {
      final harness = await _openSheet(
        tester,
        _harness(
          multiCatalog,
          model: const ModelSelection(provider: 'openrouter', model: 'z-ai/glm-4.6', reasoningEffort: 'off'),
        ),
      );
      expect(find.byType(SegmentedPill<String>), findsOneWidget);
      await tester.tap(_category('OpenRouter'));
      await pumpFrames(tester, 4);
      expect(find.text('GLM 4.6'), findsOneWidget);
      expect(find.text('V41 Flash'), findsNothing);

      await tester.tap(_category('DeepSeek'));
      await pumpFrames(tester, 4);
      expect(find.text('V4 Pro'), findsOneWidget);
      expect(find.text('GLM 4.6'), findsNothing);
      expect(harness.controllers['s1']!.models, isEmpty, reason: 'filter');
      // The selected model's efforts stay on screen while browsing.
      expect(find.text('思考深度'), findsOneWidget);

      await tester.tap(find.text('V41 Flash'));
      await pumpFrames(tester, 4);
      final picked = _picked(tester, harness)!;
      expect(picked.provider, 'deepseek-official');
      expect(picked.model, 'deepseek-flash');
      expect(picked.reasoningEffort, 'off', reason: 'supported: kept');
      expect(find.text('选择模型'), findsOneWidget, reason: 'stays open');
    });

    testWidgets('a model without efforts folds the effort selector away', (tester) async {
      final harness = await _openSheet(tester, _harness(multiCatalog));
      await tester.tap(_category('OpenRouter'));
      await pumpFrames(tester, 4);
      await tester.tap(find.text('Kimi K2'));
      await pumpFrames(tester, 6);
      final picked = _picked(tester, harness)!;
      expect(picked.model, 'moonshotai/kimi-k2');
      expect(picked.reasoningEffort, isNull);
      expect(find.text('思考深度'), findsNothing);

      // Back to a model with efforts: its default comes in.
      await tester.tap(find.text('GLM 4.6'));
      await pumpFrames(tester, 6);
      expect(find.text('思考深度'), findsOneWidget);
      expect(_picked(tester, harness)!.reasoningEffort, 'high');
    });

    testWidgets('a custom model with no default starts at 中, else its lowest thinking level', (tester) async {
      final harness = await _openSheet(
        tester,
        _harness(
          customCatalog,
          model: const ModelSelection(provider: 'deepseek-official', model: 'deepseek-v4-pro', reasoningEffort: 'max'),
        ),
      );
      await tester.tap(_category('My Gateway'));
      await pumpFrames(tester, 4);
      await tester.tap(find.text('Qwen3 Coder'));
      await pumpFrames(tester, 6);
      expect(_picked(tester, harness)!.reasoningEffort, 'medium', reason: 'not 不思考');
      expect(tester.widget<SegmentedPill<String>>(find.byType(SegmentedPill<String>).last).selected, 'medium');

      await tester.tap(find.text('GLM 4.6'));
      await pumpFrames(tester, 6);
      expect(_picked(tester, harness)!.reasoningEffort, 'high', reason: 'no 中: the lowest that thinks');
    });

    testWidgets('an effort applies at once, then the sheet closes', (tester) async {
      final harness = await _openSheet(tester, _harness(testCatalog));
      await tester.tap(find.text('最高'));
      await tester.pump();
      expect(_picked(tester, harness)!.reasoningEffort, 'max');
      expect(find.text('思考深度'), findsOneWidget, reason: 'thumb first');
      await pumpFrames(tester, 8);
      expect(find.text('思考深度'), findsNothing);
      expect(find.text('V4 Pro · 最高'), findsOneWidget);
    });

    testWidgets('model rows read as selectable buttons to a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = await _openSheet(tester, _harness(testCatalog));
      expect(
        tester.getSemantics(find.bySemanticsLabel('V4 Pro, DeepSeek · deepseek-v4-pro')),
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      final flash = find.bySemanticsLabel('V41 Flash, DeepSeek · deepseek-flash');
      expect(tester.getSemantics(flash), isSemantics(isButton: true, isSelected: false, hasTapAction: true));
      tester.semantics.tap(find.semantics.byLabel('V41 Flash, DeepSeek · deepseek-flash'));
      await pumpFrames(tester, 2);
      expect(_picked(tester, harness)!.model, 'deepseek-flash');
      semantics.dispose();
    });

    testWidgets('crowded channels and model results have separate vertical lists', (tester) async {
      await _openSheet(tester, _harness(crowdedCatalog));
      expect(find.byType(SegmentedPill<String>), findsOneWidget);
      expect(find.byType(ListView), findsNWidgets(2));
      expect(tester.widget<ListView>(find.byKey(const ValueKey('model-categories'))).scrollDirection, Axis.vertical);
      await tester.tap(_category('OpenRouter'));
      await pumpFrames(tester, 4);
      expect(find.text('Kimi K2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('common provider names fit on one line', (tester) async {
      await _openSheet(tester, _harness(crowdedCatalog));
      for (final name in ['OpenRouter', 'SiliconFlow']) {
        final label = _category(name);
        expect(label, findsOneWidget);
        expect(tester.renderObject<RenderParagraph>(label).didExceedMaxLines, isFalse);
        expect(tester.getSize(label).height, lessThan(20), reason: '$name must not wrap a trailing letter');
      }
    });

    testWidgets('no key: one line and one button', (tester) async {
      await _openSheet(
        tester,
        ChatHarness(
          settings: const AppSettings(loaded: true),
          catalog: ModelCatalog.fromJson(const {'groups': <Object?>[]}),
        ),
      );
      expect(find.text('需要 API Key'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '填写 API Key'), findsOneWidget);
      // The other way in: a provider with its own Base URL and key.
      expect(find.widgetWithText(TextButton, '添加其他渠道'), findsOneWidget);
    });

    testWidgets('set up but empty: one way to the channels page', (tester) async {
      await _openSheet(
        tester,
        ChatHarness(
          settings: const AppSettings(loaded: true, customProviderIds: {'custom-mygw'}),
          catalog: ModelCatalog.fromJson(const {'groups': <Object?>[]}),
        ),
      );
      expect(find.text('暂无可用模型'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '管理渠道'), findsOneWidget);
      expect(find.text('添加其他渠道'), findsNothing);
    });
  });

  group('long names', () {
    testWidgets('a third-party name shows whole instead of one cut line', (tester) async {
      await _openSheet(tester, _harness(longNameCatalog));
      for (final name in const ['GPT 5.6 Terra', 'GPT 6 Astra']) {
        final text = find.text(name);
        expect(text, findsOneWidget);
        expect(tester.widget<Text>(text).maxLines, 2, reason: 'a long name may use a second line');
        expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse, reason: '$name fits whole');
      }
      // The channel and exact model ID remain visible in the subtitle.
      expect(find.text('ChatGPT · gpt-5.6-terra'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('long names fit in stacked rows (text ×$scale)', (tester) async {
        await _openSheetAlone(tester, longNameCatalog, textScale: scale);
        for (final name in const ['GPT 5.6 Terra', 'GPT 6 Astra']) {
          final text = find.text(name);
          expect(tester.widget<Text>(text).maxLines, 2);
          expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse, reason: '$name fits whole');
        }
        final terra = tester.getRect(_row('GPT 5.6 Terra'));
        final astra = tester.getRect(_row('GPT 6 Astra'));
        expect(terra.width, moreOrLessEquals(astra.width, epsilon: 0.5));
        expect(terra.left, moreOrLessEquals(astra.left, epsilon: 0.5));
        expect(astra.top, greaterThanOrEqualTo(terra.bottom));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('long names keep their two lines at 2× text, nothing overflows', (tester) async {
      await _openSheetAlone(tester, longNameCatalog, textScale: 2);
      expect(find.text('GPT 5.6 Terra'), findsOneWidget);
      expect(find.text('GPT 6 Astra'), findsOneWidget);
      final terra = tester.getRect(_row('GPT 5.6 Terra'));
      final astra = tester.getRect(_row('GPT 6 Astra'));
      expect(terra.left, moreOrLessEquals(astra.left, epsilon: 0.5));
      expect(astra.top, greaterThanOrEqualTo(terra.bottom));
      expect(tester.takeException(), isNull);
    });
  });

  group('geometry', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('20 in from both sides and stacked rows (text ×$scale)', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _openSheet(tester, _harness(multiCatalog));
        final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

        final pro = tester.getRect(_row('V4 Pro'));
        final flash = tester.getRect(_row('V41 Flash'));
        final categories = tester.getRect(find.byKey(const ValueKey('model-categories')));
        expect(categories.left, moreOrLessEquals(SheetTitleBar.inset, epsilon: 0.5));
        expect(pro.left - categories.right, moreOrLessEquals(8, epsilon: 0.5));
        expect(width - pro.right, moreOrLessEquals(SheetTitleBar.inset + 12, epsilon: 0.5));
        expect(pro.width, moreOrLessEquals(flash.width, epsilon: 0.5));
        expect(flash.top, greaterThanOrEqualTo(pro.bottom));
        expect(pro.height, greaterThanOrEqualTo(48));

        // A single drag handle dismisses the sheet; management is in the title bar.
        final title = tester.getRect(find.text('选择模型'));
        expect(find.byType(SheetDragHandle), findsOneWidget);
        expect(find.byTooltip('关闭'), findsNothing);
        expect(title.left, moreOrLessEquals(SheetTitleBar.inset, epsilon: 0.5));
        expect(title.right, lessThanOrEqualTo(tester.getRect(find.text('管理模型')).left));
        expect(tester.takeException(), isNull);
      });
    }
  });

  for (final brightness in Brightness.values) {
    final suffix = brightness == Brightness.dark ? 'dark' : 'light';

    group('goldens ($suffix)', () {
      testWidgets('two channels, effort shown', (tester) async {
        await _openSheet(
          tester,
          _harness(
            multiCatalog,
            model: const ModelSelection(provider: 'openrouter', model: 'z-ai/glm-4.6', reasoningEffort: 'high'),
          ),
          brightness: brightness,
        );
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/model_sheet_channels_$suffix.png'));
      });

      testWidgets('a model without efforts', (tester) async {
        await _openSheet(
          tester,
          _harness(
            multiCatalog,
            model: const ModelSelection(provider: 'openrouter', model: 'moonshotai/kimi-k2'),
          ),
          brightness: brightness,
        );
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/model_sheet_no_effort_$suffix.png'));
      });

      testWidgets('crowded channels', (tester) async {
        await _openSheet(tester, _harness(crowdedCatalog), brightness: brightness);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/model_sheet_crowded_$suffix.png'));
      });
    });
  }
}
