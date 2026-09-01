import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_data.dart';

/// Local persistence for the app data blob. Mirrors the web app's
/// localStorage usage, but under its own Flutter-specific key since the two
/// storage mechanisms are not shared — the Gist is what keeps them in sync.
class StorageService {
  static const _key = 'marley_data';
  static const _lastSyncedTsKey = 'marley_last_synced_ts';

  Future<AppData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return AppData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(AppData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data.toJson()));
  }

  /// The remote `_lastModified` as of the last time this *device* (not just
  /// this app session) actually confirmed it against the server — see
  /// `AppState._lastSyncedTs` for why this has to survive an app restart:
  /// without it, every cold start would look exactly like a conflict the
  /// first time it compares against the remote.
  Future<int?> loadLastSyncedTs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastSyncedTsKey);
  }

  Future<void> saveLastSyncedTs(int ts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSyncedTsKey, ts);
  }
}
