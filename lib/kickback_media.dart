import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'kickback_hub_settings.dart';

class KickBackAsset {
  final String sha256;
  final String mimeType;
  final Uint8List bytes;

  const KickBackAsset({required this.sha256, required this.mimeType, required this.bytes});
}

class KickBackMedia {
  static const int maxBytes = 4 * 1024 * 1024;

  static Future<KickBackAsset?> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty || bytes.length > maxBytes) {
      throw StateError('Choose an image smaller than 4 MB.');
    }
    final mime = _mimeFor(file.extension);
    return KickBackAsset(
      sha256: sha256.convert(bytes).toString(),
      mimeType: mime,
      bytes: Uint8List.fromList(bytes),
    );
  }

  static Future<void> saveLocal(KickBackAsset asset) async {
    final dir = await _assetDirectory();
    final file = File('${dir.path}/${asset.sha256}');
    if (!await file.exists()) await file.writeAsBytes(asset.bytes, flush: true);
    final meta = File('${dir.path}/${asset.sha256}.mime');
    if (!await meta.exists()) await meta.writeAsString(asset.mimeType, flush: true);
  }

  static Future<Uint8List?> readLocal(String sha) async {
    final file = File('${(await _assetDirectory()).path}/$sha');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  static Future<bool> upload(HubSettings settings, KickBackAsset asset) async {
    final host = settings.isRemote ? settings.host : '127.0.0.1';
    final uri = Uri(
      scheme: 'http',
      host: host,
      port: settings.ipcPort,
      path: '/api/assets/${asset.sha256}',
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 3));
      if (settings.isRemote && settings.token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${settings.token}');
      }
      request.headers.contentType = ContentType.parse(asset.mimeType);
      request.headers.set('X-Omni-Asset-Sha256', asset.sha256);
      request.contentLength = asset.bytes.length;
      request.add(asset.bytes);
      final response = await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Uint8List?> fetch(HubSettings settings, String sha) async {
    final local = await readLocal(sha);
    if (local != null) return local;
    final host = settings.isRemote ? settings.host : '127.0.0.1';
    final uri = Uri(scheme: 'http', host: host, port: settings.ipcPort, path: '/api/assets/$sha');
    final headers = !settings.isRemote || settings.token.isEmpty
        ? <String, String>{}
        : {'Authorization': 'Bearer ${settings.token}'};
    try {
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final bytes = Uint8List.fromList(response.bodyBytes);
      final actual = sha256.convert(bytes).toString();
      if (actual != sha) return null;
      await saveLocal(KickBackAsset(sha256: sha, mimeType: 'application/octet-stream', bytes: bytes));
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> _assetDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}kickback_assets');
    await dir.create(recursive: true);
    return dir;
  }

  static String _mimeFor(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'heic': return 'image/heic';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      default: return 'application/octet-stream';
    }
  }
}
