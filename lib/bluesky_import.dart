/// The second inbound link: Bluesky -> KickBack.
///
/// Same shape as the Mastodon slice (mastodon_import.dart): the user's own
/// Bluesky account is read back through the public AT Protocol API. No
/// token, no OAuth, no account stored, no hosted service: for public
/// accounts the resolve / profile / feed endpoints on public.api.bsky.app
/// answer without credentials (verified live Nov 14 and again Nov 26).
///
/// Ownership: same as Mastodon. The app shows a code derived from the
/// identity's PUBLIC key; the user pastes it into their Bluesky bio; the
/// app re-reads the profile and imports only when the code is there. It
/// is a public link between the two accounts, not a secret.
///
/// Imported posts are signed by this app's key like any other post, and
/// the payload carries where they came from (platform, account, post URI,
/// original URL and time), so the provenance is part of the signed
/// record, not a display trick. Only original public posts are imported:
/// no reposts, no replies.
///
/// No Flutter imports, so parsing and mapping are unit-testable.
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The public AT Protocol API host. No key, no login.
const String kBlueskyPublicApiHost = 'public.api.bsky.app';

/// How many recent posts one import pass looks at.
const int kBlueskyImportLimit = 20;

/// A parsed Bluesky handle: a domain name, e.g. kiroba.bsky.social.
class BlueskyHandle {
  final String handle;
  const BlueskyHandle(this.handle);

  /// The full address as Bluesky writes it: @handle.
  String get full => '@$handle';

  @override
  String toString() => full;
}

/// Parses what a user types for their Bluesky account: `you.bsky.social`,
/// `@you.bsky.social`, or a profile URL like
/// `https://bsky.app/profile/you.bsky.social`. Null when nothing usable
/// is left. Custom domains work the same way - any handle is a domain.
BlueskyHandle? parseBlueskyHandle(String input) {
  var a = input.trim();
  if (a.isEmpty) return null;
  if (a.contains('://')) {
    final uri = Uri.tryParse(a);
    if (uri == null || uri.host.isEmpty) return null;
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.length < 2 || seg[0] != 'profile') return null;
    a = seg[1];
  }
  a = a.replaceFirst(RegExp(r'^@'), '');
  if (!RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
          r'(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$')
      .hasMatch(a)) {
    return null;
  }
  return BlueskyHandle(a.toLowerCase());
}

/// The public claim an account makes to prove it belongs to the same
/// person as this app's identity. The same code as the Mastodon slice:
/// derived from the identity's PUBLIC key, so it is safe to print in a
/// bio: it proves the link, it is not a secret.
String blueskyVerifyCode(String pubkeyHex) {
  if (pubkeyHex.length < 8) return 'omni-verify-$pubkeyHex';
  return 'omni-verify-${pubkeyHex.substring(0, 8)}';
}

/// True when the profile's bio contains [code]. A Bluesky profile carries
/// one bio text (`description`); there are no Mastodon-style profile
/// fields to check.
bool blueskyProfileClaimsCode(Map<String, dynamic> profile, String code) {
  if (code.isEmpty) return false;
  final bio = profile['description'];
  return bio is String && bio.contains(code);
}

/// One importable Bluesky post, already reduced to plain text.
class BlueskyPost {
  /// The AT Protocol URI: at://did:plc:.../app.bsky.feed.post/<rkey>.
  /// Stable and unique; it is the dedupe key.
  final String uri;
  final DateTime createdAt;
  final String text;
  final String url;
  const BlueskyPost({
    required this.uri,
    required this.createdAt,
    required this.text,
    required this.url,
  });

  /// Builds one importable post from one getAuthorFeed item, or null for
  /// anything that is not an original post by the account: a repost
  /// (reason), a reply (record.reply), a non-post record, or a post whose
  /// text is empty.
  static BlueskyPost? fromFeedItem(Map<String, dynamic> item, String handle) {
    final reason = item['reason'];
    if (reason is Map &&
        reason[r'$type'] == 'app.bsky.feed.defs#reasonRepost') {
      return null;
    }
    final post = item['post'];
    if (post is! Map<String, dynamic>) return null;
    final record = post['record'];
    if (record is! Map<String, dynamic>) return null;
    if (record[r'$type'] != 'app.bsky.feed.post') return null;
    if (record['reply'] != null) return null;
    final uri = post['uri'];
    final created = DateTime.tryParse('${record['createdAt']}');
    final text = record['text'];
    if (uri is! String || created == null) return null;
    if (text is! String || text.trim().isEmpty) return null;
    final rkey = uri.split('/').last;
    if (rkey.isEmpty) return null;
    return BlueskyPost(
      uri: uri,
      createdAt: created,
      text: text.trim(),
      url: 'https://bsky.app/profile/$handle/post/$rkey',
    );
  }
}

/// The payload of the KICKBACK_POST event an imported post becomes.
/// `text` is what the feed and the daemon read; `imported_from` is the
/// provenance, signed as part of the event.
Map<String, dynamic> blueskyImportPayload(
        BlueskyPost p, BlueskyHandle handle) =>
    {
      'text': p.text,
      'app': 'kickback',
      'imported_from': {
        'platform': 'bluesky',
        'account': handle.full,
        'status_id': p.uri,
        'url': p.url,
        'posted_at': p.createdAt.toUtc().toIso8601String(),
      },
    };

/// Bluesky post URIs already in the local log, read back out of post
/// payloads, so a re-import never doubles a post.
Set<String> importedBlueskyPostUris(
    Iterable<Map<String, dynamic>> payloads) {
  final out = <String>{};
  for (final p in payloads) {
    final src = p['imported_from'];
    if (src is Map && src['platform'] == 'bluesky') {
      final id = src['status_id'];
      if (id is String) out.add(id);
    }
  }
  return out;
}

/// A user-readable import failure.
class BlueskyImportException implements Exception {
  final String message;
  BlueskyImportException(this.message);
  @override
  String toString() => message;
}

/// The read-only Bluesky API client. Public endpoints only; nothing is
/// ever written to Bluesky and no credential exists to send.
class BlueskyClient {
  final http.Client _http;
  BlueskyClient([http.Client? client]) : _http = client ?? http.Client();

  /// The DID for [handle] from the public directory.
  Future<String> resolveHandle(BlueskyHandle handle) async {
    final uri = Uri.https(kBlueskyPublicApiHost,
        '/xrpc/com.atproto.identity.resolveHandle', {'handle': handle.handle});
    final body = await _get(uri);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['did'] is! String) {
      throw BlueskyImportException(
          'That handle did not resolve on Bluesky.');
    }
    return decoded['did'] as String;
  }

  /// The public profile for [handle]: did, handle, display name, bio.
  Future<Map<String, dynamic>> lookupProfile(BlueskyHandle handle) async {
    final uri = Uri.https(kBlueskyPublicApiHost,
        '/xrpc/app.bsky.actor.getProfile', {'actor': handle.handle});
    final body = await _get(uri);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['did'] is! String) {
      throw BlueskyImportException(
          'That account did not answer as expected on Bluesky.');
    }
    return decoded;
  }

  /// The account's most recent importable posts, newest first.
  Future<List<BlueskyPost>> recentPosts(String did, String handle,
      {int limit = kBlueskyImportLimit}) async {
    final uri = Uri.https(kBlueskyPublicApiHost,
        '/xrpc/app.bsky.feed.getAuthorFeed', {
      'actor': did,
      'limit': '$limit',
      'filter': 'posts_no_replies',
    });
    final body = await _get(uri);
    final decoded = jsonDecode(body);
    final feed = decoded is Map<String, dynamic> ? decoded['feed'] : null;
    if (feed is! List) {
      throw BlueskyImportException(
          'The timeline did not answer as expected on Bluesky.');
    }
    final out = <BlueskyPost>[];
    for (final item in feed) {
      if (item is Map<String, dynamic>) {
        final p = BlueskyPost.fromFeedItem(item, handle);
        if (p != null) out.add(p);
      }
    }
    return out;
  }

  Future<String> _get(Uri uri) async {
    final http.Response res;
    try {
      res = await _http.get(uri).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw BlueskyImportException(
          'Could not reach Bluesky. Check the connection and the handle.');
    }
    if (res.statusCode == 400) {
      throw BlueskyImportException('No such account on Bluesky.');
    }
    if (res.statusCode != 200) {
      throw BlueskyImportException(
          'Bluesky answered ${res.statusCode}. Try again in a bit.');
    }
    return res.body;
  }
}
