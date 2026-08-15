/// BYOK (Bring Your Own Key) AI provider settings and client service.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/task_decomposition.dart';

enum AiProvider { openAi, anthropic, custom }

final class ByokAiConfig {
  const ByokAiConfig({
    required this.apiKey,
    this.provider = AiProvider.openAi,
    this.modelName = 'gpt-4o-mini',
    this.baseUrl = 'https://api.openai.com/v1',
  });

  final String apiKey;
  final AiProvider provider;
  final String modelName;
  final String baseUrl;

  bool get isConfigured => apiKey.trim().isNotEmpty;
}

final class ByokAiService {
  ByokAiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _prefApiKey = 'byok_ai_api_key';
  static const _prefProvider = 'byok_ai_provider';
  static const _prefModel = 'byok_ai_model';
  static const _prefBaseUrl = 'byok_ai_base_url';

  Future<ByokAiConfig> loadConfig() async {
    final prefs = SharedPreferencesAsync();
    final key = await prefs.getString(_prefApiKey) ?? '';
    final providerStr = await prefs.getString(_prefProvider) ?? 'openAi';
    final model = await prefs.getString(_prefModel) ?? 'gpt-4o-mini';
    final url =
        await prefs.getString(_prefBaseUrl) ?? 'https://api.openai.com/v1';

    final provider = AiProvider.values.firstWhere(
      (p) => p.name == providerStr,
      orElse: () => AiProvider.openAi,
    );

    return ByokAiConfig(
      apiKey: key,
      provider: provider,
      modelName: model,
      baseUrl: url,
    );
  }

  Future<void> saveConfig(ByokAiConfig config) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(_prefApiKey, config.apiKey.trim());
    await prefs.setString(_prefProvider, config.provider.name);
    await prefs.setString(_prefModel, config.modelName.trim());
    await prefs.setString(_prefBaseUrl, config.baseUrl.trim());
  }

  Future<List<DecomposedSubTask>> decomposeTaskWithAi({
    required String taskTitle,
    required ByokAiConfig config,
  }) async {
    if (!config.isConfigured) return const [];

    final endpoint = Uri.parse(
      '${config.baseUrl.replaceAll(RegExp(r'/$'), '')}/chat/completions',
    );

    final response = await _client.post(
      endpoint,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey}',
      },
      body: jsonEncode({
        'model': config.modelName,
        'messages': [
          {
            'role': 'system',
            'content':
                'You are a task decomposition assistant. Output JSON format only: {"subtasks": [{"title": "step title", "minutes": 30}]}',
          },
          {
            'role': 'user',
            'content':
                'Break down this goal/task into 3-5 actionable steps: "$taskTitle"',
          },
        ],
        'temperature': 0.3,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('AI request failed: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) return const [];

    final message = (choices.first as Map)['message'] as Map;
    final content = message['content'] as String;

    final parsed = jsonDecode(content) as Map<String, Object?>;
    final subtasksJson = parsed['subtasks'] as List?;
    if (subtasksJson == null) return const [];

    return subtasksJson.map((item) {
      final map = item as Map;
      return DecomposedSubTask(
        title: map['title'] as String? ?? 'Sub-task',
        estimatedMinutes: (map['minutes'] as num?)?.toInt() ?? 30,
      );
    }).toList();
  }
}
