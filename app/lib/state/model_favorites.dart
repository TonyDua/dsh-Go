import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hosts_state.dart';

/// A local favorite is scoped to the Host and the exact DSH route. A relay's
/// cached display name is deliberately not part of its identity.
String modelFavoriteKey(HostRef host, ModelInfo model) =>
    jsonEncode([host.kind.name, host.id, model.provider, model.id]);

class ModelFavoritesController extends Notifier<Set<String>> {
  static const preferenceKey = 'model_favorites_v1';
  late Future<void> _loaded;
  Future<void> _writes = Future.value();
  bool _loadFailed = false;

  @override
  Set<String> build() {
    _loaded = _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (ref.mounted) state = Set.unmodifiable(prefs.getStringList(preferenceKey) ?? const []);
    } catch (_) {
      // Do not overwrite a potentially existing list after an unsuccessful read.
      _loadFailed = true;
    }
  }

  Future<void> toggle(String key) {
    final operation = _writes.then((_) async {
      await _loaded;
      if (!ref.mounted) return;
      final prefs = await SharedPreferences.getInstance();
      if (_loadFailed) {
        await prefs.reload();
        if (!ref.mounted) return;
        state = Set.unmodifiable(prefs.getStringList(preferenceKey) ?? const []);
        _loadFailed = false;
      }
      final next = {...state};
      if (!next.add(key)) next.remove(key);
      try {
        if (!await prefs.setStringList(preferenceKey, next.toList())) {
          throw StateError('Could not save model favorite');
        }
      } catch (_) {
        // SharedPreferences updates its in-memory cache before awaiting the
        // platform write; restore it from storage after a failed write.
        try {
          await prefs.reload();
        } catch (_) {
          _loadFailed = true;
        }
        rethrow;
      }
      if (ref.mounted) state = Set.unmodifiable(next);
    });
    // A failed write must not prevent the next action from running.
    _writes = operation.catchError((Object _) {});
    return operation;
  }
}

final modelFavoritesProvider = NotifierProvider<ModelFavoritesController, Set<String>>(ModelFavoritesController.new);
