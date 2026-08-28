import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/app_data.dart';

const _dataFileName = 'marley-data.json';

class GistSyncBlockedException implements Exception {
  final String message;
  GistSyncBlockedException(this.message);
  @override
  String toString() => message;
}

/// Talks to a single file (`marley-data.json`) in a secret GitHub Gist,
/// with 24 rotating hourly backup files (`marley-bk-00h.json` ..
/// `marley-bk-23h.json`). Deliberately has no "just sync it" method: the
/// orchestration (when it's safe to push vs. when a conflict needs a human
/// decision) lives in [AppState], which is the only place that knows what
/// this device last actually saw on the server.
class GistSyncService {
  final _secureStorage = const FlutterSecureStorage();
  static const _patKey = 'marley_gist_pat';
  static const _gistIdKey = 'marley_gist_id';

  Future<String?> getPat() => _secureStorage.read(key: _patKey);
  Future<String?> getGistId() => _secureStorage.read(key: _gistIdKey);

  Future<bool> hasCredentials() async {
    final pat = await getPat();
    final id = await getGistId();
    return pat != null && pat.isNotEmpty && id != null && id.isNotEmpty;
  }

  Future<void> setCredentials(
      {required String pat, required String gistId}) async {
    await _secureStorage.write(key: _patKey, value: pat.trim());
    await _secureStorage.write(key: _gistIdKey, value: gistId.trim());
  }

  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: _patKey);
    await _secureStorage.delete(key: _gistIdKey);
  }

  Map<String, String> _headers(String pat) => {
        'Authorization': 'token $pat',
        'Accept': 'application/vnd.github+json',
      };

  /// Fetches the whole gist metadata (files list, sizes, etc). Returns null
  /// if credentials are missing.
  Future<Map<String, dynamic>?> _fetchGistMeta() async {
    final pat = await getPat();
    final gistId = await getGistId();
    if (pat == null || gistId == null) return null;
    final resp = await http.get(
      Uri.parse('https://api.github.com/gists/$gistId'),
      headers: _headers(pat),
    );
    if (resp.statusCode != 200) {
      throw Exception(
          'Falha ao buscar Gist (${resp.statusCode}): ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<AppData?> fetchRemote() async {
    final meta = await _fetchGistMeta();
    if (meta == null) return null;
    final files = meta['files'] as Map<String, dynamic>?;
    final file = files?[_dataFileName] as Map<String, dynamic>?;
    if (file == null) return null;

    var content = file['content'] as String?;
    final truncated = file['truncated'] as bool? ?? false;
    if (truncated) {
      final rawUrl = file['raw_url'] as String;
      // Secret-gist raw content is fetchable without auth once you know the
      // URL — deliberately omit the Authorization header here.
      final rawResp = await http.get(Uri.parse(rawUrl));
      if (rawResp.statusCode != 200) {
        throw Exception(
            'Falha ao buscar conteúdo completo do Gist (${rawResp.statusCode})');
      }
      content = rawResp.body;
    }
    if (content == null || content.trim().isEmpty) return null;
    return AppData.fromJson(jsonDecode(content) as Map<String, dynamic>);
  }

  /// Pushes [data] to the Gist, writing both the canonical file and the
  /// current hourly backup slot. Blocks (throws) if the new payload is
  /// suspiciously smaller than what's already there, as a guard against
  /// silently overwriting good data with a corrupted/empty local state.
  Future<void> pushData(AppData data) async {
    final pat = await getPat();
    final gistId = await getGistId();
    if (pat == null || gistId == null) {
      throw StateError('Credenciais do Gist não configuradas.');
    }

    final content = jsonEncode(data.toJson());
    final newSize = utf8.encode(content).length;

    final meta = await _fetchGistMeta();
    final files = meta?['files'] as Map<String, dynamic>?;
    final prevFile = files?[_dataFileName] as Map<String, dynamic>?;
    final prevSize = (prevFile?['size'] as num?)?.toInt();

    if (prevSize != null && prevSize > 0 && newSize < prevSize * 0.7) {
      throw GistSyncBlockedException(
        'Push bloqueado: novo conteúdo tem $newSize bytes, menos de 70% do '
        'tamanho anterior ($prevSize bytes). Isso pode indicar perda de dados.',
      );
    }

    final hourSlot = DateTime.now().toUtc().hour.toString().padLeft(2, '0');
    final backupFileName = 'marley-bk-${hourSlot}h.json';

    final resp = await http.patch(
      Uri.parse('https://api.github.com/gists/$gistId'),
      headers: {..._headers(pat), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'files': {
          _dataFileName: {'content': content},
          backupFileName: {'content': content},
        },
      }),
    );

    if (resp.statusCode != 200) {
      throw Exception(
          'Falha ao enviar dados ao Gist (${resp.statusCode}): ${resp.body}');
    }
  }

  /// Just the remote's `_lastModified`, without adopting anything — used to
  /// check for a conflict before a background/silent push.
  Future<int?> fetchRemoteLastModified() async {
    final remote = await fetchRemote();
    return remote?.lastModified;
  }
}
