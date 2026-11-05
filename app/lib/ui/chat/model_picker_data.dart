import 'package:dsh_client/dsh_client.dart';

/// A display grouping only. [model] retains the Host's exact provider and ID;
/// a Magpie source name must never be sent back as a DSH provider.
class PickerModel {
  const PickerModel({required this.model, required this.channel, required this.source, required this.routing});

  final ModelInfo model;
  final String channel;
  final String source;
  final bool routing;

  bool matches(String query) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    final text = '${model.name}\n${model.id}\n${model.provider}\n$channel\n$source\n${model.description ?? ''}'
        .toLowerCase();
    return words.every(text.contains);
  }
}

class PickerGroup {
  const PickerGroup({
    required this.key,
    required this.name,
    required this.iconId,
    required this.models,
    this.routing = false,
    this.viaMagpie = false,
  });

  final String key;
  final String name;
  final String iconId;
  final List<PickerModel> models;
  final bool routing;
  final bool viaMagpie;
}

bool _magpie(String id) => const {
  'magpie',
  'magpie-responses',
  'magpie-anthropic',
  'custom-magpie',
  'custom-magpie-responses',
  'custom-magpie-anthropic',
}.contains(id);

String _sourceName(String id) => switch (id.toLowerCase()) {
  'deepseek' => 'DeepSeek',
  'openai' || 'codex' || 'openai-codex' => 'OpenAI',
  'anthropic' || 'claude' => 'Claude',
  'google' || 'gemini' => 'Google',
  'zhipu' || 'zai' || 'z-ai' => 'Zhipu',
  'moonshot' || 'kimi' => 'Kimi',
  'qwen' || 'aliyun' => 'Qwen',
  'minimax' => 'MiniMax',
  'mistral' => 'Mistral',
  'xai' || 'x-ai' => 'xAI',
  'openrouter' => 'OpenRouter',
  'siliconflow' || 'siliconcloud' => 'SiliconFlow',
  'volcengine' => 'Volcengine',
  'modelscope' => 'ModelScope',
  'github-copilot' || 'copilot' => 'GitHub Copilot',
  'ollama' => 'Ollama',
  'groq' => 'Groq',
  'together' || 'togetherai' => 'Together AI',
  'nvidia' => 'NVIDIA',
  'stepfun' => 'StepFun',
  _ => id,
};

/// Preserves every original model and its DSH route, even when model IDs or
/// Magpie provider IDs repeat. `auto/` is Magpie's usual public route prefix;
/// older Magpie installations can also have a provider named auto, so this is
/// a visual grouping, never a claim about or a rewrite of the actual route.
List<PickerGroup> modelPickerGroups(ModelCatalog catalog) {
  final groups = <String, PickerGroup>{};
  for (final channel in catalog.groups) {
    for (final model in channel.models) {
      final slash = model.id.indexOf('/');
      final source = slash > 0 ? model.id.substring(0, slash) : '';
      final magpie = _magpie(channel.id.toLowerCase());
      final route = magpie && (source == 'group' || source == 'auto');
      final key = route
          ? 'magpie:routing'
          : magpie && source.isNotEmpty
          ? 'magpie:provider:$source'
          : 'host:${channel.id}';
      final name = route
          ? ''
          : magpie && source.isNotEmpty
          ? _sourceName(source)
          : channel.name;
      final icon = route
          ? ''
          : magpie && source.isNotEmpty
          ? source
          : channel.id;
      final existing = groups[key];
      final item = PickerModel(
        model: model,
        channel: channel.name,
        source: route ? 'routing route group auto 路由 路由组' : name,
        routing: route,
      );
      if (existing != null) {
        existing.models.add(item);
      } else {
        groups[key] = PickerGroup(
          key: key,
          name: name,
          iconId: icon,
          routing: route,
          viaMagpie: magpie,
          models: [item],
        );
      }
    }
  }
  final ordered = groups.values.toList();
  final routeAt = ordered.indexWhere((g) => g.routing);
  if (routeAt > 0) ordered.insert(0, ordered.removeAt(routeAt));
  return ordered;
}
