import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'bluesky_import.dart';

/// ============================================================================
/// KICKBACK BLUESKY LINK: the Bluesky account whose public posts this app
/// may import (see bluesky_import.dart).
/// ============================================================================
/// A link is saved ONLY after the account's public profile was seen carrying
/// this identity's verify code - presence in this store means "verified",
/// there is no unverified saved state. The account handle is public
/// information; it is kept in the same Keystore-encrypted storage as the
/// other app settings for consistency. No Bluesky credential exists or is
/// stored: the import reads public endpoints only. The DID is saved
/// alongside the handle so the import reads the same account the user
/// verified, even if the handle later moves.
/// ============================================================================
class BlueskyLink {
  final BlueskyHandle handle;
  final String did;
  const BlueskyLink(this.handle, this.did);
}

class BlueskyLinkStore {
  static const String _kHandle = 'kickback_bluesky_handle_v1';
  static const String _kDid = 'kickback_bluesky_did_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Never throws: any storage problem or unparsable value reads as
  /// "not linked".
  static Future<BlueskyLink?> load() async {
    try {
      final handleRaw = await _storage.read(key: _kHandle);
      final did = await _storage.read(key: _kDid);
      if (handleRaw == null || did == null || did.isEmpty) return null;
      final handle = parseBlueskyHandle(handleRaw);
      if (handle == null) return null;
      return BlueskyLink(handle, did);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(BlueskyLink link) async {
    await _storage.write(key: _kHandle, value: link.handle.handle);
    await _storage.write(key: _kDid, value: link.did);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kHandle);
    await _storage.delete(key: _kDid);
  }
}
