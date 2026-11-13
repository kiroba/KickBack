/// The first inbound link: Mastodon -> KickBack.
///
/// The outbound half (mastodon_share.dart) hands a post to Mastodon's
/// website. This half reads the user's own Mastodon account back through
/// the instance's public API. No token, no OAuth, no account stored, no
/// hosted service: for public accounts the lookup and statuses endpoints
/// answer without credentials (verified live against mastodon.social).
///
/// Ownership: before anything is imported, the account must publicly claim
/// this app's identity. The app shows a code derived from the identity's
/// PUBLIC key; the user pastes it into their Mastodon bio or a profile
/// field; the app re-reads the account and imports only when the code is
/// there. It is a public link between the two accounts, not a secret.
///
/// Imported posts are signed by this app's key like any other post, and
/// the payload carries where they came from (platform, account, status
/// id, original URL and time), so the provenance is part of the signed
/// record, not a display trick. Only original public posts are imported:
/// no boosts, no replies, nothing followers-only or quieter.
///
/// No Flutter imports, so parsing and mapping are unit-testable.
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The instance used when the user gives a bare username.
const String kDefaultMastodonInstance = 'mastodon.social';

/// How many recent posts one import pass looks at.
const int kMastodonImportLimit = 20;

/// A parsed Mastodon address: a username on an instance.
class MastodonAcct {
  final String username;
  final String instance;
  const MastodonAcct(this.username, this.instance);

  /// The full address as Mastodon writes it: @user@instance.
  String get full => '@$username@$instance';

  @override
  String toString() => full;
}

/// Parses what a user types for their Mastodon account: `@user@instance`,
/// `user@instance`, `@user` (default instance), or a profile URL like
/// `https://instance/@user`. Null when nothing usable is left.
MastodonAcct? parseMastodonAcct(String input) {
  var a = input.trim();
  if (a.isEmpty) return null;
  if (a.contains('://')) {
    final uri = Uri.tryParse(a);
    if (uri == null || uri.host.isEmpty) return null;
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.isEmpty || !seg.last.startsWith('@')) return null;
    a = '${seg.last}@${uri.host}';
  }
  a = a.replaceFirst(RegExp(r'^@'), '');
  final parts = a.split('@');
  final String username;
  final String instance;
  if (parts.length == 1) {
    username = parts[0];
    instance = kDefaultMastodonInstance;
  } else if (parts.length == 2) {
    username = parts[0];
    instance = parts[1];
  } else {
    return null;
  }
  if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(username)) return null;
  if (!RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$').hasMatch(instance)) {
    return null;
  }
  return MastodonAcct(username, instance.toLowerCase());
}

/// The public claim an account makes to prove it belongs to the same
/// person as this app's identity. Derived from the identity's PUBLIC key,
/// so it is safe to print in a bio: it proves the link, it is not a secret.
String mastodonVerifyCode(String pubkeyHex) {
  if (pubkeyHex.length < 8) return 'omni-verify-$pubkeyHex';
  return 'omni-verify-${pubkeyHex.substring(0, 8)}';
}

/// True when the account's public profile (bio or any profile field)
/// contains [code]. Bio and field values arrive as HTML; the code is
/// plain text and survives tag stripping.
bool mastodonAccountClaimsCode(Map<String, dynamic> account, String code) {
  if (code.isEmpty) return false;
  final note = account['note'];
  if (note is String && mastodonHtmlToText(note).contains(code)) return true;
  final fields = account['fields'];
  if (fields is List) {
    for (final f in fields) {
      if (f is Map && f['value'] is String) {
        if (mastodonHtmlToText(f['value'] as String).contains(code)) {
          return true;
        }
      }
    }
  }
  return false;
}

/// Mastodon post content is HTML. Converts it to the plain text a KickBack
/// post carries: paragraphs and line breaks become newlines, tags go away,
/// entities are unescaped. Link URLs survive: Mastodon splits a URL into
/// spans whose text concatenates back to the full address.
String mastodonHtmlToText(String html) {
  var s = html;
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s.replaceAll('&nbsp;', ' ');
  s = s.replaceAll('&lt;', '<');
  s = s.replaceAll('&gt;', '>');
  s = s.replaceAll('&quot;', '"');
  s = s.replaceAll('&apos;', "'");
  s = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final n = int.tryParse(m.group(1)!, radix: 16);
    return n == null ? m.group(0)! : String.fromCharCode(n);
  });
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final n = int.tryParse(m.group(1)!);
    return n == null ? m.group(0)! : String.fromCharCode(n);
  });
  s = s.replaceAll('&amp;', '&');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// One importable Mastodon post, already reduced to plain text.
class MastodonStatus {
  final String id;
  final DateTime createdAt;
  final String text;
  final String url;
  const MastodonStatus({
    required this.id,
    required this.createdAt,
    required this.text,
    required this.url,
  });

  /// Builds one importable status, or null for anything that is not an
  /// original public post: a boost, a reply, a non-public visibility, or
  /// a post whose text is empty once the HTML is stripped.
  static MastodonStatus? fromJson(Map<String, dynamic> j) {
    if (j['reblog'] != null) return null;
    if (j['in_reply_to_id'] != null) return null;
    if (j['visibility'] != 'public') return null;
    final id = j['id'];
    final url = j['url'];
    final created = DateTime.tryParse('${j['created_at']}');
    final content = j['content'];
    if (id is! String || url is! String || created == null) return null;
    if (content is! String) return null;
    final text = mastodonHtmlToText(content);
    if (text.isEmpty) return null;
    return MastodonStatus(id: id, createdAt: created, text: text, url: url);
  }
}

/// The payload of the KICKBACK_POST event an imported status becomes.
/// `text` is what the feed and the daemon read; `imported_from` is the
/// provenance, signed as part of the event.
Map<String, dynamic> mastodonImportPayload(
        MastodonStatus s, MastodonAcct acct) =>
    {
      'text': s.text,
      'app': 'kickback',
      'imported_from': {
        'platform': 'mastodon',
        'account': acct.full,
        'status_id': s.id,
        'url': s.url,
        'posted_at': s.createdAt.toUtc().toIso8601String(),
      },
    };

/// Mastodon status ids already in the local log, read back out of post
/// payloads, so a re-import never doubles a post.
Set<String> importedMastodonStatusIds(
    Iterable<Map<String, dynamic>> payloads) {
  final out = <String>{};
  for (final p in payloads) {
    final src = p['imported_from'];
    if (src is Map && src['platform'] == 'mastodon') {
      final id = src['status_id'];
      if (id is String) out.add(id);
    }
  }
  return out;
}

/// A user-readable import failure.
class MastodonImportException implements Exception {
  final String message;
  MastodonImportException(this.message);
  @override
  String toString() => message;
}

/// The read-only Mastodon API client. Public endpoints only; nothing is
/// ever written to the instance and no credential exists to send.
class MastodonClient {
  final http.Client _http;
  MastodonClient([http.Client? client]) : _http = client ?? http.Client();

  /// The account object for [acct] from its own instance.
  Future<Map<String, dynamic>> lookupAccount(MastodonAcct acct) async {
    final uri = Uri.https(acct.instance, '/api/v1/accounts/lookup',
        {'acct': acct.username});
    final body = await _get(uri, acct.instance);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['id'] is! String) {
      throw MastodonImportException(
          'That account did not answer as expected on ${acct.instance}.');
    }
    return decoded;
  }

  /// The account's most recent importable statuses, newest first.
  Future<List<MastodonStatus>> recentStatuses(
      MastodonAcct acct, String accountId,
      {int limit = kMastodonImportLimit}) async {
    final uri = Uri.https(
        acct.instance, '/api/v1/accounts/$accountId/statuses', {
      'limit': '$limit',
      'exclude_replies': 'true',
      'exclude_reblogs': 'true',
    });
    final body = await _get(uri, acct.instance);
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw MastodonImportException(
          'The timeline did not answer as expected on ${acct.instance}.');
    }
    final out = <MastodonStatus>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        final s = MastodonStatus.fromJson(item);
        if (s != null) out.add(s);
      }
    }
    return out;
  }

  Future<String> _get(Uri uri, String instance) async {
    final http.Response res;
    try {
      res = await _http
          .get(uri)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw MastodonImportException(
          'Could not reach $instance. Check the connection and the address.');
    }
    if (res.statusCode == 404) {
      throw MastodonImportException('No such account on $instance.');
    }
    if (res.statusCode != 200) {
      throw MastodonImportException(
          '$instance answered ${res.statusCode}. Try again in a bit.');
    }
    return res.body;
  }
}
