import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ProjectLocalCache {
  static const String _cacheFileName = 'projects_cache.json';
  static const String _queueFileName = 'pending_sync_actions.json';

  final _secureStorage = const FlutterSecureStorage();

  // In-memory fallback/cache to ensure quick reads and correct state behavior
  Map<String, dynamic>? _inMemoryCache;
  List<dynamic>? _inMemoryQueue;

  Future<File> _getFile(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<Map<String, dynamic>> loadCache() async {
    if (kIsWeb) {
      if (_inMemoryCache != null) return _inMemoryCache!;
      try {
        final content = await _secureStorage.read(key: _cacheFileName);
        if (content != null) {
          _inMemoryCache = jsonDecode(content) as Map<String, dynamic>;
          return _inMemoryCache!;
        }
      } catch (_) {}
      _inMemoryCache = {
        'projects': <String, dynamic>{},
        'rooms': <String, dynamic>{},
        'measurements': <String, dynamic>{},
        'layouts': <String, dynamic>{},
        'lastSyncTime': null,
      };
      return _inMemoryCache!;
    }

    try {
      final file = await _getFile(_cacheFileName);
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {
      'projects': <String, dynamic>{},
      'rooms': <String, dynamic>{},
      'measurements': <String, dynamic>{},
      'layouts': <String, dynamic>{},
      'lastSyncTime': null,
    };
  }

  Future<void> saveCache(Map<String, dynamic> cache) async {
    if (kIsWeb) {
      _inMemoryCache = cache;
      try {
        await _secureStorage.write(key: _cacheFileName, value: jsonEncode(cache));
      } catch (_) {}
      return;
    }

    try {
      final file = await _getFile(_cacheFileName);
      await file.writeAsString(jsonEncode(cache));
    } catch (_) {}
  }

  Future<List<dynamic>> loadQueue() async {
    if (kIsWeb) {
      if (_inMemoryQueue != null) return _inMemoryQueue!;
      try {
        final content = await _secureStorage.read(key: _queueFileName);
        if (content != null) {
          _inMemoryQueue = jsonDecode(content) as List<dynamic>;
          return _inMemoryQueue!;
        }
      } catch (_) {}
      _inMemoryQueue = [];
      return _inMemoryQueue!;
    }

    try {
      final file = await _getFile(_queueFileName);
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveQueue(List<dynamic> queue) async {
    if (kIsWeb) {
      _inMemoryQueue = queue;
      try {
        await _secureStorage.write(key: _queueFileName, value: jsonEncode(queue));
      } catch (_) {}
      return;
    }

    try {
      final file = await _getFile(_queueFileName);
      await file.writeAsString(jsonEncode(queue));
    } catch (_) {}
  }

  Future<void> clearAll() async {
    if (kIsWeb) {
      _inMemoryCache = null;
      _inMemoryQueue = null;
      try {
        await _secureStorage.delete(key: _cacheFileName);
        await _secureStorage.delete(key: _queueFileName);
      } catch (_) {}
      return;
    }

    try {
      final cacheFile = await _getFile(_cacheFileName);
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
      final queueFile = await _getFile(_queueFileName);
      if (await queueFile.exists()) {
        await queueFile.delete();
      }
    } catch (_) {}
  }
}
