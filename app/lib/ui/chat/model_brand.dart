import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_icons.dart';

/// Known identities only. Unknown custom gateways use a neutral initial, not
/// a guessed logo. Asset sources and licences are in THIRD_PARTY_NOTICES.md.
String? modelProviderIcon(String raw) {
  final id = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return switch (id) {
    'magpie' ||
    'magpieresponses' ||
    'magpieanthropic' ||
    'custommagpie' ||
    'custommagpieresponses' ||
    'custommagpieanthropic' => 'magpie',
    'deepseek' || 'deepseekofficial' => 'deepseek-color',
    'openai' || 'chatgpt' || 'codex' || 'openaicodex' => 'openai',
    'anthropic' || 'claude' || 'claudecode' => 'claude-color',
    'google' || 'gemini' => 'google-color',
    'zhipu' || 'zai' || 'zhipuai' => 'zhipu-color',
    'moonshot' || 'moonshotai' || 'kimi' => 'kimi',
    'qwen' => 'qwen-color',
    'aliyun' || 'bailian' => 'bailian-color',
    'minimax' => 'minimax-color',
    'mistral' || 'mistralai' => 'mistral-color',
    'xai' || 'grok' => 'xai',
    'openrouter' => 'openrouter',
    'siliconflow' || 'siliconcloud' => 'siliconcloud-color',
    'volcengine' || 'ark' => 'volcengine-color',
    'modelscope' => 'modelscope-color',
    'ollama' => 'ollama',
    'githubcopilot' || 'copilot' => 'githubcopilot',
    'groq' => 'groq',
    'together' || 'togetherai' => 'together-color',
    'nvidia' => 'nvidia-color',
    'stepfun' => 'stepfun-color',
    'doubao' => 'doubao-color',
    'xiaomi' || 'mimo' => 'mimocode',
    _ => null,
  };
}

String? _familyIcon(String value) {
  final id = value.toLowerCase().trim();
  if (id.startsWith('deepseek')) return 'deepseek-color';
  if (id.startsWith('claude')) return 'claude-color';
  if (id.startsWith('gpt') || id.startsWith('codex') || RegExp(r'^o[134](?:\b|[-_.])').hasMatch(id)) return 'openai';
  if (id.startsWith('gemini') || id.startsWith('gemma')) return 'gemini-color';
  if (id.startsWith('qwen') || id.startsWith('qwq')) return 'qwen-color';
  if (id.startsWith('glm')) return 'zhipu-color';
  if (id.startsWith('kimi') || id.startsWith('moonshot')) return 'kimi';
  if (id.startsWith('minimax')) return 'minimax-color';
  if (id.startsWith('mistral') || id.startsWith('codestral') || id.startsWith('devstral')) return 'mistral-color';
  if (id.startsWith('grok')) return 'xai';
  if (id.startsWith('doubao')) return 'doubao-color';
  if (id.startsWith('mimo')) return 'mimocode';
  if (id.startsWith('step')) return 'stepfun-color';
  return null;
}

String? modelFamilyIcon(ModelInfo model) {
  final id = model.id;
  final slash = id.indexOf('/');
  final tail = slash < 0 ? id : id.substring(slash + 1);
  return _familyIcon(tail) ?? _familyIcon(model.name) ?? modelProviderIcon(model.provider);
}

class ModelBrand extends StatelessWidget {
  const ModelBrand({super.key, required this.label, this.icon, this.routing = false, this.size = 32});

  final String label;
  final String? icon;
  final bool routing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = routing
        ? Icon(AppIcons.subagents, size: size * .55, color: colors.primary)
        : Text(
            label.trim().isEmpty ? '?' : label.trim().characters.first.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
          );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.onSurface.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(size * .27),
          ),
          child: Center(
            child: icon == null
                ? fallback
                : SvgPicture.asset(
                    'assets/model_brands/$icon.svg',
                    width: size * .66,
                    height: size * .66,
                    theme: SvgTheme(currentColor: colors.onSurface),
                    errorBuilder: (_, _, _) => fallback,
                  ),
          ),
        ),
      ),
    );
  }
}
