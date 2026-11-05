import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/model_favorites.dart';
import 'package:dsh_app/ui/chat/model_brand.dart';
import 'package:dsh_app/ui/chat/model_picker_data.dart';
import 'package:dsh_app/ui/chat/model_sheet.dart';
import 'package:dsh_app/ui/common/app_sheet.dart' show SheetDragHandle;
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/harness.dart';

class FailOncePreferences extends InMemorySharedPreferencesStore {
  FailOncePreferences() : super.empty();
  bool fail = true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (key == 'flutter.${ModelFavoritesController.preferenceKey}' && fail) {
      fail = false;
      return Future.value(false);
    }
    return super.setValue(valueType, key, value);
  }
}

final catalog138 = ModelCatalog(
  defaultSelection: const ModelSelection(
    provider: 'deepseek-official',
    model: 'deepseek-v4-pro',
    reasoningEffort: 'high',
  ),
  routableProviders: const ['magpie', 'magpie-responses', 'deepseek-official'],
  groups: [
    ProviderGroup('magpie', 'Magpie', [
      for (var i = 0; i < 110; i++) ModelInfo(provider: 'magpie', id: 'openai/gpt-6-$i', name: 'GPT-6 Model $i'),
      for (var i = 0; i < 20; i++) ModelInfo(provider: 'magpie', id: 'qwen/qwen-$i', name: 'Qwen $i'),
      const ModelInfo(provider: 'magpie', id: 'group/fast', name: '快速路由'),
      const ModelInfo(provider: 'magpie', id: 'group/quality', name: '复杂任务路由'),
      const ModelInfo(provider: 'magpie', id: 'auto/gpt', name: '自动选择 GPT'),
      const ModelInfo(
        provider: 'magpie',
        id: 'zhipu/glm-5.3',
        name: 'GLM-5.3',
        efforts: [ReasoningEffort('low', 'Low', null), ReasoningEffort('high', 'High', null)],
        defaultEffort: 'high',
      ),
    ]),
    const ProviderGroup('magpie-responses', 'Magpie · Responses', [
      ModelInfo(provider: 'magpie-responses', id: 'openai/gpt-6-0', name: 'GPT-6 Model 0'),
      ModelInfo(provider: 'magpie-responses', id: 'openai/gpt-6-a', name: 'GPT-6 Astra'),
      ModelInfo(provider: 'magpie-responses', id: 'openai/gpt-6-b', name: 'GPT-6 Sol'),
    ]),
    ...testCatalog.groups.take(1).map((g) => ProviderGroup(g.id, g.name, [g.models.first])),
  ],
  failures: const [],
);

Future<void> openPicker(
  WidgetTester tester,
  ValueChanged<ModelSelection> onSelected, {
  double textScale = 1,
  Brightness brightness = Brightness.light,
  bool confirmSelection = false,
  ModelCatalog? catalog,
}) async {
  usePhoneView(tester);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final currentCatalog = catalog ?? catalog138;
  final harness = ChatHarness(catalog: currentCatalog);
  await tester.pumpWidget(
    testApp(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showModelSheet(
              context,
              current: currentCatalog.defaultSelection,
              onSelected: onSelected,
              confirmSelection: confirmSelection,
            ),
            child: const Text('打开模型'),
          ),
        ),
      ),
      overrides: harness.overrides,
      brightness: brightness,
    ),
  );
  await pumpFrames(tester, 4);
  await tester.tap(find.text('打开模型'));
  await pumpFrames(tester, 8);
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Magpie sources and routing groups preserve exact DSH provider and model identity', () {
    expect(catalog138.models.length, 138);
    final groups = modelPickerGroups(catalog138);
    final routes = groups.singleWhere((g) => g.routing);
    expect(routes.models.map((m) => m.model.id), ['group/fast', 'group/quality', 'auto/gpt']);
    expect(routes.models.every((m) => m.matches('路由组') && m.matches('routing')), isTrue);
    final openai = groups.singleWhere((g) => g.key == 'magpie:provider:openai');
    expect(openai.models.length, 113);
    expect(openai.models.where((m) => m.model.id == 'openai/gpt-6-0').map((m) => m.model.provider), [
      'magpie',
      'magpie-responses',
    ]);
    expect(groups.singleWhere((g) => g.key == 'magpie:provider:zhipu').models.single.matches('magpie glm-5.3'), isTrue);
  });

  test('a Magpie channel created in DSH still uses its original custom route', () {
    final custom = ModelCatalog(
      defaultSelection: null,
      routableProviders: const ['custom-magpie'],
      groups: const [
        ProviderGroup('custom-magpie', 'Magpie', [
          ModelInfo(provider: 'custom-magpie', id: 'openai/gpt-6', name: 'GPT-6'),
          ModelInfo(provider: 'custom-magpie', id: 'group/fast', name: 'Fast'),
        ]),
      ],
      failures: const [],
    );
    final groups = modelPickerGroups(custom);
    expect(groups.singleWhere((g) => g.routing).models.single.model.provider, 'custom-magpie');
    expect(groups.singleWhere((g) => g.key == 'magpie:provider:openai').models.single.model.id, 'openai/gpt-6');
  });

  test('favorites survive reload and distinguish hosts and identical IDs on different routes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const a = ModelInfo(provider: 'magpie', id: 'openai/gpt-6-0', name: 'GPT');
    const b = ModelInfo(provider: 'magpie-responses', id: 'openai/gpt-6-0', name: 'GPT');
    final one = modelFavoriteKey(const HostRef.ssh('one'), a);
    final otherRoute = modelFavoriteKey(const HostRef.ssh('one'), b);
    final otherHost = modelFavoriteKey(const HostRef.ssh('two'), a);
    expect({one, otherRoute, otherHost}, hasLength(3));
    await Future.wait([
      container.read(modelFavoritesProvider.notifier).toggle(one),
      container.read(modelFavoritesProvider.notifier).toggle(otherRoute),
      container.read(modelFavoritesProvider.notifier).toggle(otherHost),
    ]);
    expect(container.read(modelFavoritesProvider), {one, otherRoute, otherHost});
    final stored = (await SharedPreferences.getInstance()).getStringList(ModelFavoritesController.preferenceKey)!;
    expect(stored.toSet(), {one, otherRoute, otherHost});
    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    reloaded.read(modelFavoritesProvider);
    await Future<void>.delayed(Duration.zero);
    expect(reloaded.read(modelFavoritesProvider), {one, otherRoute, otherHost});
  });

  testWidgets('138 models are lazy, searchable, and pick the exact Magpie route', (tester) async {
    ModelSelection? picked;
    await openPicker(tester, (value) => picked = value);
    final starButtons = find.byWidgetPredicate(
      (widget) => widget is IconButton && (widget.tooltip?.startsWith('添加星标') ?? false),
    );
    expect(starButtons.evaluate().length, lessThan(20), reason: 'off-screen rows are not constructed');
    await tester.enterText(find.byKey(const ValueKey('model-search')), 'glm-5.3');
    await pumpFrames(tester, 4);
    expect(find.text('GLM 5.3'), findsOneWidget);
    await tester.tap(find.text('GLM 5.3'));
    await pumpFrames(tester, 4);
    expect(picked?.provider, 'magpie');
    expect(picked?.model, 'zhipu/glm-5.3');
    expect(picked?.reasoningEffort, 'high');
    expect(tester.takeException(), isNull);
  });

  testWidgets('stars persist locally and the favorites view filters the model', (tester) async {
    await openPicker(tester, (_) {});
    await tester.enterText(find.byKey(const ValueKey('model-search')), 'glm-5.3');
    await pumpFrames(tester, 4);
    final star = find.byTooltip('添加星标 · GLM 5.3');
    expect(tester.getSize(star).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(star).height, greaterThanOrEqualTo(48));
    await tester.tap(star);
    await pumpFrames(tester, 5);
    expect(find.byTooltip('取消星标 · GLM 5.3'), findsOneWidget);
    await tester.tap(find.text('星标'));
    await pumpFrames(tester, 4);
    expect(find.text('GLM 5.3'), findsOneWidget);
    final stored = (await SharedPreferences.getInstance()).getStringList(ModelFavoritesController.preferenceKey);
    expect(stored, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation mode saves the exact route only after approval', (tester) async {
    ModelSelection? picked;
    await openPicker(tester, (value) => picked = value, confirmSelection: true);
    await tester.enterText(find.byKey(const ValueKey('model-search')), 'glm-5.3');
    await pumpFrames(tester, 4);
    await tester.tap(find.text('GLM 5.3'));
    await pumpFrames(tester, 4);
    expect(picked, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await pumpFrames(tester, 8);
    expect(picked?.provider, 'magpie');
    expect(picked?.model, 'zhipu/glm-5.3');
  });

  testWidgets('many source categories and model results scroll independently', (tester) async {
    final lotsOfSources = ModelCatalog(
      defaultSelection: catalog138.defaultSelection,
      routableProviders: const [],
      groups: [
        ...catalog138.groups,
        for (var i = 0; i < 20; i++)
          ProviderGroup('source-$i', 'Source $i', [ModelInfo(provider: 'source-$i', id: 'm-$i', name: 'Model $i')]),
      ],
      failures: const [],
    );
    await openPicker(tester, (_) {}, catalog: lotsOfSources);
    final sourceList = find.byKey(const ValueKey('model-categories'));
    final resultList = find.byKey(const ValueKey('model-results-all'));
    final results = tester.state<ScrollableState>(find.descendant(of: resultList, matching: find.byType(Scrollable)));
    final before = results.position.pixels;
    await tester.drag(sourceList, const Offset(0, -500));
    await pumpFrames(tester, 4);
    expect(results.position.pixels, before);
    expect(
      tester.state<ScrollableState>(find.descendant(of: sourceList, matching: find.byType(Scrollable))).position.pixels,
      greaterThan(0),
    );
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale) in [(390.0, 1.0), (390.0, 2.0), (320.0, 1.0), (320.0, 2.0)]) {
    testWidgets('scrollbars have a separate gutter at $width dp and ${scale}x text', (tester) async {
      final catalog = ModelCatalog(
        defaultSelection: const ModelSelection(provider: 'magpie', model: 'group/fast'),
        routableProviders: catalog138.routableProviders,
        groups: [
          ...catalog138.groups,
          for (var i = 0; i < 20; i++)
            ProviderGroup('source-$i', 'Source $i', [ModelInfo(provider: 'source-$i', id: 'm-$i', name: 'Model $i')]),
        ],
        failures: const [],
      );
      await openPicker(tester, (_) {}, textScale: scale, catalog: catalog);
      tester.view.physicalSize = Size(width * 2, 1688);
      await tester.pump();
      final categories = find.byKey(const ValueKey('model-categories'));
      final results = find.byKey(const ValueKey('model-results-all'));
      final categoryBox = find.ancestor(of: find.text('全部'), matching: find.byType(Material)).first;
      final modelBox = find.ancestor(of: find.text('快速路由'), matching: find.byType(Material)).first;
      final categoryRect = tester.getRect(categoryBox);
      final categoryViewport = tester.getRect(categories);
      final modelRect = tester.getRect(modelBox);
      final resultViewport = tester.getRect(results);
      final starRect = tester.getRect(find.byTooltip('添加星标 · 快速路由'));
      final heading = tester.getRect(find.text('路由组 · 经 Magpie'));
      final modelIcon = tester.getRect(find.descendant(of: modelBox, matching: find.byType(ModelBrand)));
      final categoryScrollbar = tester.widget<Scrollbar>(
        find.ancestor(of: categories, matching: find.byType(Scrollbar)).first,
      );
      final resultScrollbar = tester.widget<Scrollbar>(
        find.ancestor(of: results, matching: find.byType(Scrollbar)).first,
      );
      final margin = ScrollbarTheme.of(tester.element(categories)).crossAxisMargin ?? 0;
      final categoryThumbLeft = categoryViewport.right - margin - (categoryScrollbar.thickness ?? 4);
      final resultThumbLeft = resultViewport.right - margin - (resultScrollbar.thickness ?? 4);
      expect(categoryThumbLeft - categoryRect.right, greaterThanOrEqualTo(6.5));
      expect(resultThumbLeft - modelRect.right, greaterThanOrEqualTo(6.5));
      expect(starRect.right, lessThanOrEqualTo(modelRect.right + .5));
      expect(categoryRect.width, greaterThanOrEqualTo(48));
      expect(modelRect.height, greaterThanOrEqualTo(48));
      expect(heading.left, moreOrLessEquals(modelIcon.left, epsilon: .5));
      expect(tester.getRect(find.text('全部')).center.dx, moreOrLessEquals(categoryRect.center.dx, epsilon: .5));
      final categoryScroll = tester.state<ScrollableState>(
        find.descendant(of: categories, matching: find.byType(Scrollable)),
      );
      final resultScroll = tester.state<ScrollableState>(
        find.descendant(of: results, matching: find.byType(Scrollable)),
      );
      expect(categoryScroll.position.maxScrollExtent, greaterThan(0));
      expect(resultScroll.position.maxScrollExtent, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, height) in [(390.0, 844.0), (320.0, 568.0)]) {
    testWidgets('Android visible scrollbars stay clear of both selected rectangles at ${width}x$height', (
      tester,
    ) async {
      final firstGroup = catalog138.groups.first;
      final catalog = ModelCatalog(
        defaultSelection: const ModelSelection(provider: 'magpie', model: 'group/fast', reasoningEffort: 'high'),
        routableProviders: catalog138.routableProviders,
        groups: [
          ProviderGroup(firstGroup.id, firstGroup.name, [
            const ModelInfo(
              provider: 'magpie',
              id: 'group/fast',
              name: '快速路由',
              efforts: [ReasoningEffort('off', 'Off', null), ReasoningEffort('high', 'High', null)],
              defaultEffort: 'high',
            ),
            ...firstGroup.models.where((m) => m.id != 'group/fast'),
          ]),
          ...catalog138.groups.skip(1),
          for (var i = 0; i < 20; i++)
            ProviderGroup('source-$i', 'Source $i', [ModelInfo(provider: 'source-$i', id: 'm-$i', name: 'Model $i')]),
        ],
        failures: const [],
      );
      await openPicker(tester, (_) {}, brightness: Brightness.dark, catalog: catalog);
      tester.view.physicalSize = Size(width * 2, height * 2);
      await pumpFrames(tester, 4);
      final categories = find.byKey(const ValueKey('model-categories'));
      final results = find.byKey(const ValueKey('model-results-all'));
      final categoryBox = find.ancestor(of: find.text('全部'), matching: find.byType(Material)).first;
      final modelBox = find.ancestor(of: find.text('快速路由'), matching: find.byType(Material)).first;
      for (final (list, box) in [(categories, categoryBox), (results, modelBox)]) {
        final scroll = tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)));
        final bar = tester.widget<Scrollbar>(find.ancestor(of: list, matching: find.byType(Scrollbar)).first);
        final margin = ScrollbarTheme.of(tester.element(list)).crossAxisMargin ?? 0;
        final thumbLeft = tester.getRect(list).right - margin - (bar.thickness ?? 4);
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        expect(bar.thumbVisibility, isTrue);
        expect(thumbLeft - tester.getRect(box).right, greaterThanOrEqualTo(6.5));
      }
      expect(find.text('思考深度'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/model_picker_scrollbars_${width.toInt()}_android_dark.png'),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  for (final (width, height, scale) in [(390.0, 844.0, 1.0), (320.0, 568.0, 2.0)]) {
    testWidgets('search and effort stay fixed while lists scroll at ${width}x$height and ${scale}x text', (
      tester,
    ) async {
      final catalog = ModelCatalog(
        defaultSelection: catalog138.defaultSelection,
        routableProviders: catalog138.routableProviders,
        groups: [
          ...catalog138.groups,
          for (var i = 0; i < 20; i++)
            ProviderGroup('source-$i', 'Source $i', [ModelInfo(provider: 'source-$i', id: 'm-$i', name: 'Model $i')]),
        ],
        failures: const [],
      );
      await openPicker(tester, (_) {}, textScale: scale, catalog: catalog);
      tester.view.physicalSize = Size(width * 2, height * 2);
      await pumpFrames(tester, 4);
      final categories = find.byKey(const ValueKey('model-categories'));
      final results = find.byKey(const ValueKey('model-results-all'));
      final search = find.byKey(const ValueKey('model-search'));
      final effort = scale == 2 ? find.byKey(const ValueKey('compact-model-effort')) : find.text('思考深度');
      final searchBefore = tester.getRect(search);
      final effortBefore = tester.getRect(effort);
      final categoryScroll = tester.state<ScrollableState>(
        find.descendant(of: categories, matching: find.byType(Scrollable)),
      );
      final resultScroll = tester.state<ScrollableState>(
        find.descendant(of: results, matching: find.byType(Scrollable)),
      );
      await tester.drag(results, const Offset(0, -100));
      await pumpFrames(tester, 4);
      expect(resultScroll.position.pixels, greaterThan(0));
      expect(tester.getRect(search), searchBefore);
      expect(tester.getRect(effort), effortBefore);
      await tester.drag(categories, const Offset(0, -100));
      await pumpFrames(tester, 4);
      expect(categoryScroll.position.pixels, greaterThan(0));
      expect(tester.getRect(search), searchBefore);
      expect(tester.getRect(effort), effortBefore);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a failed favorite write preserves search and allows retry', (tester) async {
    SharedPreferencesStorePlatform.instance = FailOncePreferences();
    await openPicker(tester, (_) {});
    await tester.enterText(find.byKey(const ValueKey('model-search')), 'glm-5.3');
    await pumpFrames(tester, 4);
    await tester.tap(find.byTooltip('添加星标 · GLM 5.3'));
    await pumpFrames(tester, 5);
    expect(find.text('星标保存失败，请重试'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('model-search'))).controller?.text, 'glm-5.3');
    expect(find.byTooltip('添加星标 · GLM 5.3'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getStringList(ModelFavoritesController.preferenceKey), isNull);
    await tester.tap(find.byTooltip('添加星标 · GLM 5.3'));
    await pumpFrames(tester, 5);
    expect(find.byTooltip('取消星标 · GLM 5.3'), findsOneWidget);
  });

  testWidgets('all bundled SVG logos decode in Flutter', (tester) async {
    const names = [
      'bailian-color',
      'claude-color',
      'deepseek-color',
      'doubao-color',
      'gemini-color',
      'githubcopilot',
      'google-color',
      'groq',
      'kimi',
      'magpie',
      'mimocode',
      'minimax-color',
      'mistral-color',
      'modelscope-color',
      'nvidia-color',
      'ollama',
      'openai',
      'openrouter',
      'qwen-color',
      'siliconcloud-color',
      'stepfun-color',
      'together-color',
      'volcengine-color',
      'xai',
      'zai',
      'zhipu-color',
    ];
    for (final name in names) {
      final picture = await vg.loadPicture(SvgAssetLoader('assets/model_brands/$name.svg'), null);
      expect(picture.size.width, greaterThan(0), reason: name);
      expect(picture.size.height, greaterThan(0), reason: name);
      picture.picture.dispose();
    }
  });

  testWidgets('search remains usable on a small phone with the keyboard and large text', (tester) async {
    await openPicker(tester, (_) {}, textScale: 2);
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.viewInsets = const FakeViewPadding(bottom: 520);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('model-search')), 'glm-5.3');
    await pumpFrames(tester, 4);
    expect(find.text('GLM 5.3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard keeps search and effort visible while the category list scrolls', (tester) async {
    await openPicker(tester, (_) {}, brightness: Brightness.dark, textScale: 2);
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.viewInsets = const FakeViewPadding(bottom: 520);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('model-search')), 'glm-5.3');
    await pumpFrames(tester, 4);
    final search = find.byKey(const ValueKey('model-search'));
    final effort = find.byKey(const ValueKey('compact-model-effort'));
    final categories = find.byKey(const ValueKey('model-categories'));
    final results = find.byKey(const ValueKey('model-results-all'));
    final searchBefore = tester.getRect(search);
    final effortBefore = tester.getRect(effort);
    expect(find.byType(SheetDragHandle), findsNothing);
    expect(effortBefore.bottom, lessThanOrEqualTo(308));
    expect(tester.getRect(results).bottom, lessThanOrEqualTo(effortBefore.top));
    final scroll = tester.state<ScrollableState>(find.descendant(of: categories, matching: find.byType(Scrollable)));
    await tester.drag(categories, const Offset(0, -40));
    await pumpFrames(tester, 4);
    expect(scroll.position.pixels, greaterThan(0));
    expect(tester.getRect(search), searchBefore);
    expect(tester.getRect(effort), effortBefore);
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/model_picker_keyboard_large_dark.png'));
    tester.view.viewInsets = FakeViewPadding.zero;
    await pumpFrames(tester, 4);
    expect(find.byType(SheetDragHandle), findsOneWidget);
  });

  testWidgets('compact large-text effort menu remains selectable', (tester) async {
    ModelSelection? picked;
    await openPicker(tester, (value) => picked = value, textScale: 2);
    tester.view.physicalSize = const Size(640, 1136);
    await pumpFrames(tester, 4);
    expect(find.text('快速路由'), findsOneWidget);
    expect(find.text('思考深度 · 高'), findsOneWidget);
    final row = find.ancestor(of: find.text('快速路由'), matching: find.byType(Material)).first;
    final viewport = find.byKey(const ValueKey('model-results-all'));
    expect(tester.getRect(row).bottom, lessThanOrEqualTo(tester.getRect(viewport).bottom));
    await tester.tap(find.byKey(const ValueKey('compact-model-effort')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('最高'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最高'));
    await tester.pumpAndSettle();
    expect(picked?.reasoningEffort, 'max');
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact confirmation can choose and save when no model was selected', (tester) async {
    ModelSelection? picked;
    final noDefault = ModelCatalog(
      defaultSelection: null,
      routableProviders: catalog138.routableProviders,
      groups: catalog138.groups,
      failures: const [],
    );
    await openPicker(tester, (value) => picked = value, textScale: 2, catalog: noDefault, confirmSelection: true);
    tester.view.physicalSize = const Size(640, 1136);
    await pumpFrames(tester, 4);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('快速路由'));
    await pumpFrames(tester, 2);
    await tester.tap(find.text('快速路由'));
    await pumpFrames(tester, 4);
    expect(picked, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await pumpFrames(tester, 8);
    expect(picked?.provider, 'magpie');
    expect(picked?.model, 'group/fast');
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape search keeps results reachable with the keyboard', (tester) async {
    await openPicker(tester, (_) {}, textScale: 1.3);
    tester.view.physicalSize = const Size(1688, 780);
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('model-search')), 'glm-5.3');
    await pumpFrames(tester, 4);
    expect(find.text('GLM 5.3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Magpie phone picker golden', (tester) async {
    await openPicker(tester, (_) {}, brightness: Brightness.dark);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/model_picker_magpie_dark.png'));
  });

  testWidgets('Magpie phone picker at 2x text golden', (tester) async {
    await openPicker(tester, (_) {}, brightness: Brightness.dark, textScale: 2);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/model_picker_magpie_2x_dark.png'));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Magpie picker on a 320x568 phone at ${scale}x text', (tester) async {
      await openPicker(tester, (_) {}, brightness: Brightness.dark, textScale: scale);
      tester.view.physicalSize = const Size(640, 1136);
      await pumpFrames(tester, 4);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/model_picker_compact_${scale == 1 ? 'normal' : 'large'}_dark.png'),
      );
    });
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('large picker remains laid out on a phone at text scale $scale', (tester) async {
      await openPicker(tester, (_) {}, textScale: scale);
      expect(find.byKey(const ValueKey('model-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
