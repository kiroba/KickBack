import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'mastodon_import.dart';

/// ============================================================================
/// KICKBACK MASTODON LINK: the Mastodon account whose public posts this app
/// may import (see mastodon_import.dart).
/// ============================================================================
/// A link is saved ONLY after the account's public profile was seen carrying
/// this identity's verify code - presence in this store means "verified",
/// there is no unverified saved state. The account address is public
/// information; it is kept in the same Keystore-encrypted storage as the
/// other app settings for consistency. No Mastodon credential exists or is
/// stored: the import reads public endpoints only.
/// ============================================================================
class MastodonLink {
  final MastodonAcct acct;
  final String accountId;
  const MastodonLink(this.acct, this.accountId);
}

class MastodonLinkStore {
  static const String _kAcct = 'kickback_mastodon_acct_v1';
  static const String _kAccountId = 'kickback_mastodon_account_id_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Never throws: any storage problem or unparsable value reads as
  /// "not linked".
  static Future<MastodonLink?> load() async {
    try {
      final acctRaw = await _storage.read(key: _kAcct);
      final id = await _storage.read(key: _kAccountId);
      if (acctRaw == null || id == null || id.isEmpty) return null;
      final acct = parseMastodonAcct(acctRaw);
      if (acct == null) return null;
      return MastodonLink(acct, id);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(MastodonLink link) async {
    await _storage.write(key: _kAcct, value: link.acct.full);
    await _storage.write(key: _kAccountId, value: link.accountId);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kAcct);
    await _storage.delete(key: _kAccountId);
  }
}
