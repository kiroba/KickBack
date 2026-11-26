import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'peertube_import.dart';

/// ============================================================================
/// KICKBACK PEERTUBE LINK: the PeerTube account whose public videos this app
/// may import (see peertube_import.dart).
/// ============================================================================
/// A link is saved ONLY after the account's public description (or one of
/// its channels' descriptions) was seen carrying this identity's verify
/// code - presence in this store means "verified", there is no unverified
/// saved state. The account address is public information; it is kept in
/// the same Keystore-encrypted storage as the other app settings for
/// consistency. No PeerTube credential exists or is stored: the import
/// reads public endpoints only. PeerTube has no DID, so the address
/// (name@instance) is the whole link.
/// ============================================================================
class PeerTubeLink {
  final PeerTubeAccount account;
  const PeerTubeLink(this.account);
}

class PeerTubeLinkStore {
  static const String _kHandle = 'kickback_peertube_handle_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Never throws: any storage problem or unparsable value reads as
  /// "not linked".
  static Future<PeerTubeLink?> load() async {
    try {
      final handleRaw = await _storage.read(key: _kHandle);
      if (handleRaw == null) return null;
      final account = parsePeerTubeAccount(handleRaw);
      if (account == null) return null;
      return PeerTubeLink(account);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(PeerTubeLink link) async {
    await _storage.write(key: _kHandle, value: link.account.full);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kHandle);
  }
}
