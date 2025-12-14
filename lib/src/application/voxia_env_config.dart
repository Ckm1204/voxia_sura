import 'dart:convert';

import 'package:flutter/services.dart';

class VoxiaEnvConfig {
  VoxiaEnvConfig({required this.systemPrompt});

  final String systemPrompt;

  static const String _defaultPrompt =
      'Eres Voxia, un asistente de voz amable y conciso. Responde en español de forma breve y útil.';

  static Future<VoxiaEnvConfig> load({String assetPath = 'packages/sura_voxia/.env'}) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final parsed = _parseEnv(raw);
      final prompt = parsed['VOXIA_SYSTEM_PROMPT']?.trim();
      if (prompt != null && prompt.isNotEmpty) {
        return VoxiaEnvConfig(systemPrompt: prompt);
      }
    } catch (_) {
      // ignore and fallback
    }
    return VoxiaEnvConfig(systemPrompt: _defaultPrompt);
  }

  static Map<String, String> _parseEnv(String content) {
    final map = <String, String>{};
    const lineSplitter = LineSplitter();
    for (final rawLine in lineSplitter.convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final idx = line.indexOf('=');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key.isNotEmpty) map[key] = value;
    }
    return map;
  }
}