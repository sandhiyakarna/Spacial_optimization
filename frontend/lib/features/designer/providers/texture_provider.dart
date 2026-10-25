import 'package:flutter_riverpod/flutter_riverpod.dart';

class TextureCache {
  static final TextureCache _instance = TextureCache._internal();
  factory TextureCache() => _instance;
  TextureCache._internal();

  final Map<String, dynamic> _cache = {};

  void cacheTexture(String path, dynamic data) {
    _cache[path] = data;
  }

  dynamic getTexture(String path) {
    return _cache[path];
  }

  bool has(String path) {
    return _cache.containsKey(path);
  }

  void clear() {
    _cache.clear();
  }

  int get size => _cache.length;
}

class TextureNotifier extends Notifier<Map<String, String>> {
  final TextureCache _textureCache = TextureCache();

  @override
  Map<String, String> build() {
    return {};
  }

  Future<void> loadTexture(String path) async {
    if (_textureCache.has(path)) {
      return;
    }

    state = {...state, path: 'loading'};

    try {
      // Lazy loading texture simulation / future execution
      await Future.delayed(const Duration(milliseconds: 150));

      final extension = path.split('.').last.toLowerCase();
      
      // Support PNG, JPG, WEBP & Future ready KTX2, HDR formats
      String textureFormat = 'Unknown';
      if (['png', 'jpg', 'jpeg'].contains(extension)) {
        textureFormat = 'Raster (PNG/JPG)';
      } else if (extension == 'webp') {
        textureFormat = 'Compressed (WEBP)';
      } else if (extension == 'ktx2') {
        textureFormat = 'GPU Compressed (KTX2)';
      } else if (extension == 'hdr') {
        textureFormat = 'High Dynamic Range (HDR)';
      }

      // Memory optimization - Cache metadata or simulated rasterized bytes
      _textureCache.cacheTexture(path, {
        'path': path,
        'format': textureFormat,
        'loaded_at': DateTime.now(),
        'simulated_size_kb': extension == 'ktx2' ? 128 : 256,
      });

      state = {...state, path: 'loaded'};
    } catch (e) {
      state = {...state, path: 'error'};
    }
  }

  void clearCache() {
    _textureCache.clear();
    state = {};
  }

  int get cachedCount => _textureCache.size;
}

final textureProvider = NotifierProvider<TextureNotifier, Map<String, String>>(() {
  return TextureNotifier();
});
