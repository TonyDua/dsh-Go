// Portions derived from PiPilot (https://github.com/CikeSeven/pi_pilot), MIT, Copyright (c) 2026 CikeSeven. See THIRD_PARTY_NOTICES.md.
// Local changes: a glass bottom sheet fed by `session/modelCatalog`, with a
// channel filter, model cards and a capsule effort selector.

import 'dart:async';
import 'dart:math' as math;

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/hosts_state.dart';
import '../../state/model_favorites.dart';
import '../../state/models_state.dart';
import '../../state/settings_state.dart';
import '../common/app_sheet.dart';
import '../common/empty_view.dart';
import '../common/segmented_pill.dart';
import '../common/sheet_title_bar.dart';
import '../common/smooth_size.dart';
import '../common/read_list_status.dart';
import '../common/ui_trace.dart';
import '../onboarding/api_key_page.dart';
import '../providers/provider_form_page.dart';
import '../providers/providers_page.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'model_brand.dart';
import 'model_picker_data.dart';

// Scrollbar paints inside its viewport. Keep its track clear of tappable rows
// and selection backgrounds on both sides of the picker.
const _pickerScrollbarGutter = 12.0;

/// 模型名的短写:去掉 "DeepSeek-" 前缀,连字符换空格,首字母大写。
/// `DeepSeek-V4-Pro` → `V4 Pro`。
String shortModelName(String raw) {
  final stripped = raw.replaceFirst(RegExp(r'^deepseek[-_ ]?', caseSensitive: false), '');
  final words = stripped
      .split(RegExp(r'[-_ ]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w.length == 1 ? w.toUpperCase() : w[0].toUpperCase() + w.substring(1))
      .join(' ');
  return words.isEmpty ? raw : words;
}

/// 胶囊上的模型短名;没有选择时是「选择模型」。
String modelShortName(ModelSelection? selection, ModelCatalog? catalog) {
  if (selection == null) return appL10n.viewModelSelect;
  return shortModelName(findModel(catalog, selection)?.name ?? selection.model);
}

/// 思考深度的中文名。协议词(off/low/high/max)不直接给人看。
String effortLabel(String id, [String? fallback]) => switch (id) {
  'off' || 'none' => appL10n.viewModelThinkingOff,
  'minimal' => appL10n.viewModelThinkingMinimal,
  'low' => appL10n.viewModelThinkingLow,
  'medium' => appL10n.viewModelThinkingMedium,
  'high' => appL10n.viewModelThinkingHigh,
  'xhigh' => appL10n.viewModelThinkingXhigh,
  'max' => appL10n.viewModelThinkingMax,
  _ => fallback ?? id,
};

/// 顶栏右侧的模型胶囊:"✦ V4 Pro · 高 ⌄"。换模型时宽度平滑过渡、文字淡变。
///
/// 位置不够时依次让出:先收起「· 高」(读屏照读),再截短模型名,最后只留
/// ✦ 和 ⌄。给多宽由顶栏量了再定([ChatHeader]),胶囊自己不猜屏宽:它的
/// 最小固有宽度是「完整模型名、不带深度」,最大固有宽度是「名字加深度」。
class ModelChip extends ConsumerWidget {
  const ModelChip({super.key, required this.selection, required this.onSelected, this.grouped = false});

  /// 当前生效的选择;null 时显示目录默认值。
  final ModelSelection? selection;
  final ValueChanged<ModelSelection> onSelected;
  final bool grouped;

  // The chevron's glyph carries ~4 of its own air on the right: 12 + 0 on
  // the left reads the same as 8 + 4 on the right.
  static const _padStart = 12.0;
  static const _padEnd = 8.0;
  static const _glyph = 14.0;
  static const _chevron = 16.0;

  /// The narrowest the chip gets: the sparkle and the chevron, no words.
  static const compactWidth = _padStart + _glyph + _chevron + _padEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final catalog = ref.watch(currentModelCatalogProvider);
    final effective = selection ?? catalog?.defaultSelection;
    final effort = effective?.reasoningEffort;
    final label = modelShortName(effective, catalog);
    final quick = AppMotion.of(context, AppMotion.quick);
    final em = MediaQuery.textScalerOf(context).scale(13);
    final style = theme.textTheme.labelMedium?.copyWith(fontSize: 13);
    void open() => showModelSheet(context, current: effective, onSelected: onSelected);
    return GlassSurface(
      tier: GlassTier.chrome,
      stadium: true,
      grouped: grouped,
      onTap: open,
      child: Semantics(
        label: [
          l10n.viewModelLabel(label),
          if (effort != null) l10n.viewModelEffortLabel(effortLabel(effort)),
        ].join(l10n.viewListSeparator),
        button: true,
        onTap: open,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_padStart, 0, _padEnd, 0),
            child: SmoothSize(
              duration: AppMotion.of(context, AppMotion.standard),
              curve: AppMotion.std,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.model, size: _glyph, color: theme.colorScheme.primary),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: quick,
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                      child: _ChipLabel(
                        key: ValueKey('$label\u0000$effort'),
                        gap: 5,
                        // About two letters and an ellipsis; a long name
                        // stops at ten characters' width.
                        minTextWidth: em * 2.5,
                        maxTextWidth: em * 10,
                        children: [
                          if (effort != null)
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: label),
                                  TextSpan(
                                    text: ' · ${effortLabel(effort)}',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style,
                            ),
                          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                        ],
                      ),
                    ),
                  ),
                  Icon(AppIcons.expand, size: _chevron, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chip's words: the first of [children] that fits whole (the name with
/// its depth, then the name alone). The last one shortens with an ellipsis
/// when nothing fits, and the words go altogether, with the [gap] in front of
/// them, once less than [minTextWidth] would show. Never wider than
/// [maxTextWidth].
///
/// Its min intrinsic width is the last child whole, its max intrinsic width
/// the first: what the header weighs the title against.
class _ChipLabel extends MultiChildRenderObjectWidget {
  const _ChipLabel({
    super.key,
    required this.gap,
    required this.minTextWidth,
    required this.maxTextWidth,
    required super.children,
  });

  final double gap;
  final double minTextWidth;
  final double maxTextWidth;

  @override
  MultiChildRenderObjectElement createElement() => _ChipLabelElement(this);

  @override
  _RenderChipLabel createRenderObject(BuildContext context) => _RenderChipLabel(gap, minTextWidth, maxTextWidth);

  @override
  void updateRenderObject(BuildContext context, _RenderChipLabel renderObject) {
    renderObject
      ..gap = gap
      ..minTextWidth = minTextWidth
      ..maxTextWidth = maxTextWidth;
  }
}

/// Only the shown words are on stage (finders, like [IndexedStack]'s).
class _ChipLabelElement extends MultiChildRenderObjectElement {
  _ChipLabelElement(super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final shown = (renderObject as _RenderChipLabel).shown;
    for (final child in children) {
      if (shown != null && identical(child.renderObject, shown)) visitor(child);
    }
  }
}

class _ChipLabelParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderChipLabel extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ChipLabelParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ChipLabelParentData> {
  _RenderChipLabel(this._gap, this._minTextWidth, this._maxTextWidth);

  /// Rounding between the header's arithmetic and the text's own width.
  static const _slack = 0.5;

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double _minTextWidth;
  set minTextWidth(double value) {
    if (value == _minTextWidth) return;
    _minTextWidth = value;
    markNeedsLayout();
  }

  double _maxTextWidth;
  set maxTextWidth(double value) {
    if (value == _maxTextWidth) return;
    _maxTextWidth = value;
    markNeedsLayout();
  }

  /// The child on screen after the last layout; null when the words are gone.
  RenderBox? shown;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ChipLabelParentData) {
      child.parentData = _ChipLabelParentData();
    }
  }

  double _whole(RenderBox child) => math.min(child.getMaxIntrinsicWidth(double.infinity), _maxTextWidth);

  /// Which child [maxWidth] shows, and how wide its text may run.
  (RenderBox, double)? _pick(double maxWidth) {
    final room = math.min(maxWidth - _gap, _maxTextWidth);
    if (room < _minTextWidth) return null;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final whole = _whole(child);
      if (whole <= room + _slack) return (child, whole);
      if (child == lastChild) return (child, room);
    }
    return null;
  }

  @override
  double computeMinIntrinsicWidth(double height) => lastChild == null ? 0 : _gap + _whole(lastChild!);

  @override
  double computeMaxIntrinsicWidth(double height) => firstChild == null ? 0 : _gap + _whole(firstChild!);

  @override
  double computeMinIntrinsicHeight(double width) => lastChild?.getMinIntrinsicHeight(double.infinity) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) => lastChild?.getMaxIntrinsicHeight(double.infinity) ?? 0;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final pick = _pick(constraints.maxWidth);
    if (pick == null) return constraints.smallest;
    final (child, width) = pick;
    final text = child.getDryLayout(BoxConstraints(maxWidth: width));
    return constraints.constrain(Size(_gap + text.width, text.height));
  }

  @override
  void performLayout() {
    final pick = _pick(constraints.maxWidth);
    shown = pick?.$1;
    if (pick == null) {
      size = constraints.smallest;
      return;
    }
    final (child, width) = pick;
    child.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    (child.parentData! as _ChipLabelParentData).offset = Offset(_gap, 0);
    size = constraints.constrain(Size(_gap + child.size.width, child.size.height));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => shown?.getDistanceToActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = shown;
    if (child == null) return;
    final childOffset = (child.parentData! as _ChipLabelParentData).offset + offset;
    context.paintChild(child, childOffset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = shown;
    if (child == null) return false;
    final offset = (child.parentData! as _ChipLabelParentData).offset;
    return result.addWithPaintOffset(
      offset: offset,
      position: position,
      hitTest: (result, transformed) => child.hitTest(result, position: transformed),
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (shown case final child?) visitor(child);
  }
}

/// 模型弹层:点模型卡立即生效(深度沿用或取默认);选思考深度立即生效,
/// 滑块落位后弹层自己收起。
Future<void> showModelSheet(
  BuildContext context, {
  required ModelSelection? current,
  required ValueChanged<ModelSelection> onSelected,
  bool confirmSelection = false,
}) {
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    hideHandleWhenKeyboard: true,
    builder: (context) => _ModelSheet(current: current, onSelected: onSelected, confirmSelection: confirmSelection),
  );
}

/// Searchable, grouped model picker. Filtering and local favorites never
/// rewrite a model's original host/provider route.
class _ModelSheet extends ConsumerStatefulWidget {
  const _ModelSheet({required this.current, required this.onSelected, required this.confirmSelection});

  final ModelSelection? current;
  final ValueChanged<ModelSelection> onSelected;
  final bool confirmSelection;

  @override
  ConsumerState<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends ConsumerState<_ModelSheet> {
  late ModelSelection? _selection = widget.current;
  late final Object _scope = ref.read(modelSelectionScopeProvider);
  late final HostRef _host = ref.read(activeHostProvider);
  final _query = TextEditingController();
  final _categoryScroll = ScrollController();
  final _resultScroll = ScrollController(keepScrollOffset: false);

  bool get _active => identical(_scope, ref.read(modelSelectionScopeProvider));

  /// Browsing and searching do not change the selected model.
  String _category = 'all';

  /// Closes the sheet once the effort thumb has landed.
  Timer? _close;

  @override
  void dispose() {
    _close?.cancel();
    _query.dispose();
    _categoryScroll.dispose();
    _resultScroll.dispose();
    super.dispose();
  }

  void _pickModel(ModelInfo model) {
    final view = ref.read(modelListViewProvider);
    if (!_active || view.readOnly) return;
    final available = findModel(view.value, ModelSelection(provider: model.provider, model: model.id));
    if (available == null || !identical(available, model)) return;
    final keep = _selection?.reasoningEffort;
    final supported = model.efforts.any((e) => e.id == keep);
    final next = ModelSelection(
      provider: model.provider,
      model: model.id,
      reasoningEffort: supported ? keep : startingEffort(model),
    );
    setState(() {
      _selection = next;
    });
    _close?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    if (!widget.confirmSelection) widget.onSelected(next);
  }

  void _pickEffort(String effort) {
    final view = ref.read(modelListViewProvider);
    if (!_active || view.readOnly) return;
    final current = _selection;
    if (current == null) return;
    final available = findModel(view.value, current);
    if (available == null || !available.efforts.any((entry) => entry.id == effort)) return;
    final next = ModelSelection(provider: current.provider, model: current.model, reasoningEffort: effort);
    setState(() => _selection = next);
    if (widget.confirmSelection) return;
    widget.onSelected(next);
    _close?.cancel();
    final settle = AppMotion.reduced(context) ? Duration.zero : AppMotion.standard + const Duration(milliseconds: 120);
    _close = Timer(settle, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final catalogAsync = ref.watch(modelCatalogProvider);
    final view = ref.watch(modelListViewProvider);
    final catalog = view.value;
    final active = identical(_scope, ref.watch(modelSelectionScopeProvider));
    final groups = catalog == null
        ? const <ProviderGroup>[]
        : [
            for (final g in catalog.groups)
              if (g.models.isNotEmpty) g,
          ];

    if (catalog != null && groups.isNotEmpty) {
      return UiTrace(
        scope: 'models',
        child: _picker(catalog, findModel(catalog, _selection), readOnly: view.readOnly || !active),
      );
    }
    final Widget body;
    if (catalog == null) {
      body = catalogAsync.isLoading
          ? const _Loading()
          : catalogAsync.hasError
          ? EmptyView(
              padding: _emptyPadding,
              icon: AppIcons.offline,
              title: l10n.viewModelLoadFailed,
              action: FilledButton.tonal(
                onPressed: () => ref.invalidate(modelCatalogProvider),
                child: Text(l10n.commonRetry),
              ),
            )
          : EmptyView(
              padding: _emptyPadding,
              icon: AppIcons.disconnected,
              title: l10n.viewModelDisconnected,
              message: l10n.viewModelConnectHint,
            );
    } else {
      body = _EmptyCatalog(
        configured: ref.watch(settingsProvider.select((s) => s.hasModelAccess)) || catalog.failures.isNotEmpty,
        failure: catalog.failures.isEmpty ? null : catalog.failures.first.message,
      );
    }
    return UiTrace(
      scope: 'models',
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitleBar(
                catalog == null ? l10n.viewModelSelect : readListHeading(l10n.viewModelSelect, view.status),
              ),
              body,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _favorite(PickerModel entry) async {
    try {
      await ref.read(modelFavoritesProvider.notifier).toggle(modelFavoriteKey(_host, entry.model));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.l10n.viewModelFavoriteFailed)));
      }
    }
  }

  Widget _picker(ModelCatalog catalog, ModelInfo? selected, {required bool readOnly}) {
    final l10n = context.l10n;
    final view = ref.watch(modelListViewProvider);
    final favorites = ref.watch(modelFavoritesProvider);
    final groups = modelPickerGroups(catalog);
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final space = math.max(
      0.0,
      media.size.height - media.padding.top - media.viewInsets.bottom - (keyboardOpen ? 8 : 64),
    );
    final height = math.min(media.size.height * .82, space);
    final textScale = media.textScaler.scale(11) / 11;
    final railWidth = 76.0 + 16 * (textScale - 1).clamp(0.0, 1.0) + _pickerScrollbarGutter;
    final compactControls = keyboardOpen || (height < 520 && (textScale >= 1.3 || media.size.height < 440));
    final categories = [
      _PickerCategory(key: 'all', name: l10n.viewModelAll, glyph: AppIcons.modelItem),
      _PickerCategory(key: 'favorites', name: l10n.viewModelFavorites, glyph: AppIcons.favorite),
      for (final group in groups)
        _PickerCategory(
          key: group.key,
          name: group.routing ? l10n.viewModelRouting : group.name,
          iconId: group.iconId,
          routing: group.routing,
          detail: group.viaMagpie
              ? '${group.routing ? l10n.viewModelRouting : group.name} · ${l10n.viewModelViaMagpie}'
              : null,
        ),
    ];
    final category = categories.any((c) => c.key == _category) ? _category : 'all';
    final query = _query.text.trim();
    final rows = <({PickerGroup group, PickerModel? model})>[];
    for (final group in groups) {
      if (category != 'all' && category != 'favorites' && category != group.key) continue;
      final matching = [
        for (final item in group.models)
          if ((category != 'favorites' || favorites.contains(modelFavoriteKey(_host, item.model))) &&
              item.matches(query))
            item,
      ];
      if (matching.isEmpty) continue;
      if (!keyboardOpen || height > 260) rows.add((group: group, model: null));
      rows.addAll([for (final item in matching) (group: group, model: item)]);
    }
    final efforts = selected?.efforts ?? const <ReasoningEffort>[];
    var currentChannel = selected?.provider ?? '';
    if (selected != null) {
      for (final group in catalog.groups) {
        if (group.models.any((model) => identical(model, selected))) {
          currentChannel = group.name;
          break;
        }
      }
    }
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!keyboardOpen)
                SheetTitleBar(readListHeading(l10n.viewModelSelect, view.status), actions: const [ManageModelsLink()]),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  SheetTitleBar.inset,
                  0,
                  SheetTitleBar.inset,
                  keyboardOpen
                      ? 2
                      : compactControls
                      ? 8
                      : 12,
                ),
                child: TextField(
                  key: const ValueKey('model-search'),
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: media.size.width < 360 && textScale > 1.5
                        ? l10n.viewModelSearchCompact
                        : media.size.width < 360 || textScale > 1.5
                        ? l10n.viewModelSearchShort
                        : l10n.viewModelSearch,
                    prefixIcon: const Icon(AppIcons.search, size: 20),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.commonClear,
                            onPressed: () => setState(_query.clear),
                            icon: const Icon(AppIcons.clear, size: 18),
                          ),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    filled: true,
                  ),
                ),
              ),
              if (selected != null && !keyboardOpen && height > 380)
                Padding(
                  padding: const EdgeInsets.fromLTRB(SheetTitleBar.inset, 0, SheetTitleBar.inset, 8),
                  child: Tooltip(
                    message: '${l10n.viewModelCurrent}: ${shortModelName(selected.name)} · $currentChannel',
                    child: Semantics(
                      label: '${l10n.viewModelCurrent}: ${shortModelName(selected.name)} · $currentChannel',
                      excludeSemantics: true,
                      child: Text(
                        '${l10n.viewModelCurrent}: ${shortModelName(selected.name)}${compactControls ? '' : ' · $currentChannel'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: DshColors.of(context).textTertiary),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SheetTitleBar.inset),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: railWidth,
                        child: Scrollbar(
                          controller: _categoryScroll,
                          thumbVisibility: true,
                          thickness: 3,
                          radius: const Radius.circular(3),
                          child: ListView.builder(
                            key: const ValueKey('model-categories'),
                            controller: _categoryScroll,
                            padding: const EdgeInsetsDirectional.only(end: _pickerScrollbarGutter),
                            itemCount: categories.length,
                            itemBuilder: (context, i) => _CategoryTile(
                              category: categories[i],
                              selected: categories[i].key == category,
                              onTap: () => setState(() => _category = categories[i].key),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: rows.isEmpty
                            ? Center(
                                child: Text(
                                  category == 'favorites' && query.isEmpty
                                      ? l10n.viewModelNoFavorites
                                      : l10n.viewModelNoMatches,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: DshColors.of(context).textTertiary),
                                ),
                              )
                            : Scrollbar(
                                controller: _resultScroll,
                                thumbVisibility: true,
                                thickness: 3,
                                radius: const Radius.circular(3),
                                child: ListView.builder(
                                  key: ValueKey('model-results-$category'),
                                  controller: _resultScroll,
                                  padding: const EdgeInsetsDirectional.only(end: _pickerScrollbarGutter),
                                  itemCount: rows.length,
                                  itemBuilder: (context, i) {
                                    final row = rows[i];
                                    final item = row.model;
                                    if (item == null) {
                                      final label = row.group.routing ? l10n.viewModelRouting : row.group.name;
                                      final name = row.group.viaMagpie ? '$label · ${l10n.viewModelViaMagpie}' : label;
                                      return Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          8,
                                          compactControls ? 4 : 8,
                                          4,
                                          compactControls ? 2 : 6,
                                        ),
                                        child: Semantics(
                                          label: name,
                                          header: true,
                                          excludeSemantics: true,
                                          child: Text(compactControls ? label : name, style: groupTitleStyle(context)),
                                        ),
                                      );
                                    }
                                    final m = item.model;
                                    return _PickerModelRow(
                                      item: item,
                                      selected: selected?.id == m.id && selected?.provider == m.provider,
                                      starred: favorites.contains(modelFavoriteKey(_host, m)),
                                      onPick: readOnly ? null : () => _pickModel(m),
                                      onFavorite: () => unawaited(_favorite(item)),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              if (efforts.length > 1)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    SheetTitleBar.inset,
                    keyboardOpen
                        ? 2
                        : compactControls
                        ? 4
                        : 8,
                    SheetTitleBar.inset,
                    0,
                  ),
                  child: _PickerEfforts(
                    efforts: efforts,
                    selected: _selection?.reasoningEffort ?? selected?.defaultEffort ?? efforts.first.id,
                    onChanged: readOnly ? null : _pickEffort,
                    compact: compactControls,
                  ),
                ),
              if (!keyboardOpen && widget.confirmSelection && !isValidModelSelection(catalog, _selection))
                Padding(
                  padding: const EdgeInsets.fromLTRB(SheetTitleBar.inset, 8, SheetTitleBar.inset, 0),
                  child: Text(l10n.engineNewChatDefaultsSelectionUnavailable),
                ),
              if (!keyboardOpen && widget.confirmSelection)
                Padding(
                  padding: const EdgeInsets.fromLTRB(SheetTitleBar.inset, 8, SheetTitleBar.inset, 0),
                  child: FilledButton(
                    onPressed: readOnly || !isValidModelSelection(catalog, _selection)
                        ? null
                        : () {
                            final currentView = ref.read(modelListViewProvider);
                            if (!_active ||
                                currentView.readOnly ||
                                !isValidModelSelection(currentView.value, _selection)) {
                              return;
                            }
                            widget.onSelected(_selection!);
                            Navigator.of(context).pop();
                          },
                    child: Text(l10n.commonSave),
                  ),
                ),
              SizedBox(
                height: keyboardOpen
                    ? 2
                    : compactControls
                    ? 8
                    : 12,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The model-management entry in the picker title bar.
class ManageModelsLink extends StatelessWidget {
  const ManageModelsLink({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProvidersPage())),
      child: Text(l10n.nearbyManageModels),
    );
  }
}

class _PickerCategory {
  const _PickerCategory({
    required this.key,
    required this.name,
    this.glyph,
    this.iconId,
    this.detail,
    this.routing = false,
  });

  final String key;
  final String name;
  final IconData? glyph;
  final String? iconId;
  final String? detail;
  final bool routing;
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.selected, required this.onTap});

  final _PickerCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: category.detail ?? category.name,
      child: Semantics(
        button: true,
        selected: selected,
        label: category.detail ?? category.name,
        onTap: onTap,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: selected ? colors.primary.withValues(alpha: .13) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 58),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (category.glyph case final glyph?)
                        Icon(glyph, size: 20, color: selected ? colors.primary : colors.onSurfaceVariant)
                      else
                        ModelBrand(
                          label: category.name,
                          icon: modelProviderIcon(category.iconId ?? ''),
                          routing: category.routing,
                          size: 24,
                        ),
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          category.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: selected ? colors.primary : colors.onSurfaceVariant,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerModelRow extends StatelessWidget {
  const _PickerModelRow({
    required this.item,
    required this.selected,
    required this.starred,
    required this.onPick,
    required this.onFavorite,
  });

  final PickerModel item;
  final bool selected;
  final bool starred;
  final VoidCallback? onPick;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final model = item.model;
    final colors = Theme.of(context).colorScheme;
    final name = shortModelName(model.name);
    final source = '${item.channel} · ${model.id}';
    final favoriteLabel = starred ? context.l10n.viewModelRemoveFavorite : context.l10n.viewModelAddFavorite;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected ? colors.primary.withValues(alpha: .10) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                enabled: onPick != null,
                selected: selected,
                inMutuallyExclusiveGroup: true,
                label: '$name, $source',
                onTap: onPick,
                excludeSemantics: true,
                child: InkWell(
                  onTap: onPick,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 9, 0, 9),
                    child: Row(
                      children: [
                        ModelBrand(
                          label: name,
                          icon: item.routing ? null : modelFamilyIcon(model),
                          routing: item.routing,
                          size: 30,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                source,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: DshColors.of(context).textTertiary),
                              ),
                            ],
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 4),
                          Icon(AppIcons.selected, size: 16, color: colors.primary),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              visualDensity: VisualDensity.standard,
              tooltip: '$favoriteLabel · $name',
              onPressed: onFavorite,
              icon: Icon(
                starred ? AppIcons.favoriteActive : AppIcons.favorite,
                size: 19,
                color: starred ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerEfforts extends StatelessWidget {
  const _PickerEfforts({required this.efforts, required this.selected, required this.onChanged, required this.compact});

  final List<ReasoningEffort> efforts;
  final String selected;
  final ValueChanged<String>? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final labels = [for (final e in efforts) effortLabel(e.id, e.name)];
    if (compact) {
      final index = efforts.indexWhere((e) => e.id == selected);
      final currentLabel = index < 0 ? effortLabel(selected) : labels[index];
      final colors = Theme.of(context).colorScheme;
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: PopupMenuButton<String>(
          key: const ValueKey('compact-model-effort'),
          enabled: onChanged != null,
          initialValue: selected,
          onSelected: onChanged,
          itemBuilder: (context) => [
            for (var i = 0; i < efforts.length; i++)
              PopupMenuItem<String>(
                value: efforts[i].id,
                child: Row(
                  children: [
                    Expanded(child: Text(labels[i])),
                    if (efforts[i].id == selected) Icon(AppIcons.selected, size: 18, color: colors.primary),
                  ],
                ),
              ),
          ],
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.onSurface.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    '${context.l10n.viewModelEffort} · $currentLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(AppIcons.expand, size: 16, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.l10n.viewModelEffort, style: groupTitleStyle(context)),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            if (SegmentedPill.naturalWidth(context, labels) <= constraints.maxWidth) {
              return SegmentedPill<String>(
                height: 40,
                segments: [for (final e in efforts) PillSegment(e.id, effortLabel(e.id, e.name))],
                selected: selected,
                onChanged: onChanged,
              );
            }
            return SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: efforts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) => ChoiceChip(
                  label: Text(labels[i]),
                  selected: selected == efforts[i].id,
                  onSelected: onChanged == null ? null : (_) => onChanged!(efforts[i].id),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Room around an empty / failed catalog inside the sheet.
const _emptyPadding = EdgeInsets.fromLTRB(32, 16, 32, 8);

/// 目录还在路上:一颗安静的小环,高度和一排模型卡差不多,来了不跳。
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    child: Center(
      child: SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          strokeCap: StrokeCap.round,
          color: DshColors.of(context).textTertiary,
        ),
      ),
    ),
  );
}

/// 目录是空的:DSH 0.2.1 在没有可用凭据时不列任何模型。什么都没配就引导去填
/// DeepSeek 的 Key,或者添加别的渠道;配了还是空,多半是 Key 还没同步到引擎或者
/// 无效,去「模型渠道」看。
class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog({required this.configured, this.failure});

  /// A DeepSeek key or a custom provider exists.
  final bool configured;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failure = this.failure?.trim();
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    if (!configured) {
      return EmptyView(
        padding: _emptyPadding,
        icon: AppIcons.apiKey,
        title: l10n.viewModelKeyRequired,
        message: l10n.viewModelProvidersHint,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () => push(const ApiKeyPage(onboarding: false)),
              child: Text(l10n.viewModelEnterKey),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: () => push(const ProviderFormPage()), child: Text(l10n.viewModelAddProvider)),
          ],
        ),
      );
    }
    return EmptyView(
      padding: _emptyPadding,
      icon: AppIcons.noApiKey,
      title: l10n.viewModelNone,
      message: failure != null && failure.isNotEmpty ? failure : l10n.viewModelKeyHint,
      action: FilledButton(onPressed: () => push(const ProvidersPage()), child: Text(l10n.viewModelManageProviders)),
    );
  }
}
