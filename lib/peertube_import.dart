/// The third inbound link: PeerTube -> KickBack.
///
/// Same shape as the Mastodon slice (mastodon_import.dart) and the Bluesky
/// keyhole (bluesky_import.dart): the user's own PeerTube account is read
/// back through the instance's public API. No token, no OAuth, no account
/// stored, no hosted service: for public accounts the account, channels and
/// videos endpoints answer without credentials (verified live against
/// tilvids.com Nov 26, 2026 — GET /api/v1/videos, /api/v1/accounts/{name},
/// /api/v1/accounts/{name}/videos and /api/v1/video-channels/{name} all
/// answered anonymously).
///
/// PeerTube is federated: there is no central host. The instance is part of
/// the account address (`name@instance`), and every call goes to that
/// instance's own API. There is no default instance — a bare username
/// without one is rejected, so the user always knows where their videos
/// live.
///
/// Ownership: same as Mastodon and Bluesky. The app shows a code derived
/// from the identity's PUBLIC key; the user pastes it into their PeerTube
/// account description or any of their channels' descriptions; the app
/// re-reads the account and imports only when the code is there. It is a
/// public link between the two accounts, not a secret.
///
/// Imported videos are signed by this app's key like any other post, and
/// the payload carries where they came from (platform, account, video UUID,
/// watch URL and time), so the provenance is part of the signed record, not
/// a display trick. Only original public videos are imported: nothing
/// unlisted, private, or internal.
///
/// How a video differs from a text post: the feed's `text` is the video
/// title plus its description, and `imported_from` carries the video
/// fields (title, description, thumbnail URL, duration) so the record
/// keeps what the feed card cannot show. The feed's image preview only
/// renders hub-stored media by sha256, so a remote thumbnail URL is
/// carried, not rendered — the card shows the title, description and the
/// "via PeerTube" line, and the watch URL is in the signed payload.
///
/// No Flutter imports, so parsing and mapping are unit-testable.
import 'dart:convert';

import 'package:http/http.dart' as http;

/// How many recent videos one import pass looks at.
const int kPeerTubeImportLimit = 20;

/// A parsed PeerTube account address: a username on an instance.
class PeerTubeAccount {
  final String name;
  final String instance;
  const PeerTubeAccount(this.name, this.instance);

  /// The full address as PeerTube writes it: name@instance.
  String get full => '$name@$instance';

  @override
  String toString() => full;
}

/// Parses what a user types for their PeerTube account: `name@instance`,
/// `@name@instance`, or an account URL like
/// `https://instance/accounts/name`. Null when nothing usable is left.
/// A bare name is rejected: PeerTube has no central instance to default
/// to, so the instance is part of the address. Channel URLs
/// (`/video-channels/...`) are rejected too — the account, not a channel,
/// is what gets linked; a channel's videos are reached through its owner
/// account.
PeerTubeAccount? parsePeerTubeAccount(String input) {
  var a = input.trim();
  if (a.isEmpty) return null;
  if (a.contains('://')) {
    final uri = Uri.tryParse(a);
    if (uri == null || uri.host.isEmpty) return null;
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.length < 2 || seg[0] != 'accounts') return null;
    a = '${seg[1]}@${uri.host}';
  }
  a = a.replaceFirst(RegExp(r'^@'), '');
  final parts = a.split('@');
  if (parts.length != 2) return null;
  final name = parts[0];
  final instance = parts[1].toLowerCase();
  if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name)) return null;
  if (!RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$').hasMatch(instance)) {
    return null;
  }
  return PeerTubeAccount(name, instance);
}

/// The public claim an account makes to prove it belongs to the same
/// person as this app's identity. The same code as the Mastodon and
/// Bluesky slices: derived from the identity's PUBLIC key, so it is safe
/// to print in a description: it proves the link, it is not a secret.
String peertubeVerifyCode(String pubkeyHex) {
  if (pubkeyHex.length < 8) return 'omni-verify-$pubkeyHex';
  return 'omni-verify-${pubkeyHex.substring(0, 8)}';
}

/// True when the account's public description, or any of its channels'
/// descriptions, contains [code]. The account description is the bio;
/// a channel description is the same text a creator puts on their
/// channel page, so either counts as the claim.
bool peertubeAccountClaimsCode(Map<String, dynamic> account,
    List<Map<String, dynamic>> channels, String code) {
  if (code.isEmpty) return false;
  final bio = account['description'];
  if (bio is String && bio.contains(code)) return true;
  for (final c in channels) {
    final desc = c['description'];
    if (desc is String && desc.contains(code)) return true;
  }
  return false;
}

/// One importable PeerTube video, already reduced to plain fields.
class PeerTubeVideo {
  /// The video UUID: stable and unique; it is the dedupe key.
  final String uuid;

  /// The watch page URL on the instance.
  final String url;
  final String title;
  final String description;

  /// Absolute thumbnail URL, when the instance gave one.
  final String? thumbnailUrl;

  /// Length in seconds, when the instance gave one.
  final int? durationSeconds;
  final DateTime publishedAt;

  const PeerTubeVideo({
    required this.uuid,
    required this.url,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.durationSeconds,
    required this.publishedAt,
  });

  /// The text the feed card shows: the title, plus the description when
  /// the video has one.
  String get displayText =>
      description.isEmpty ? title : '$title\n\n$description';

  /// Builds one importable video, or null for anything that is not a
  /// public video with a title: unlisted / private / internal privacy,
  /// or a video with no UUID, URL, title or publish time.
  static PeerTubeVideo? fromJson(Map<String, dynamic> j, String host) {
    final privacy = j['privacy'];
    if (privacy is Map && privacy['id'] != 1) return null;
    final uuid = j['uuid'];
    final url = j['url'];
    final name = j['name'];
    final published =
        DateTime.tryParse('${j['publishedAt'] ?? j['createdAt']}');
    if (uuid is! String || uuid.isEmpty) return null;
    if (url is! String || url.isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;
    if (published == null) return null;
    final desc = j['description'];
    final duration = j['duration'];
    return PeerTubeVideo(
      uuid: uuid,
      url: url,
      title: name.trim(),
      description: desc is String ? desc.trim() : '',
      thumbnailUrl: _pickThumbnail(j, host),
      durationSeconds: duration is num ? duration.toInt() : null,
      publishedAt: published,
    );
  }

  /// The best thumbnail URL from a video object: the 1280-wide 16:9
  /// still when the instance lists one, else any 16:9 still, else the
  /// plain thumbnail path made absolute against the instance.
  static String? _pickThumbnail(Map<String, dynamic> j, String host) {
    final thumbs = j['thumbnails'];
    String? wide;
    if (thumbs is List) {
      for (final t in thumbs) {
        if (t is! Map<String, dynamic>) continue;
        final fileUrl = t['fileUrl'];
        if (fileUrl is! String || fileUrl.isEmpty) continue;
        if (t['aspectRatio'] != '16:9') continue;
        if (t['width'] == 1280) return fileUrl;
        wide ??= fileUrl;
      }
    }
    if (wide != null) return wide;
    final path = j['thumbnailPath'];
    if (path is String && path.isNotEmpty) {
      return path.startsWith('http') ? path : 'https://$host$path';
    }
    return null;
  }
}

/// The payload of the KICKBACK_POST event an imported video becomes.
/// `text` is what the feed and the daemon read; `imported_from` is the
/// provenance, signed as part of the event — including the video fields
/// the feed card does not render (title, description, thumbnail,
/// duration), so the signed record keeps the whole video, not just a
/// link to it.
Map<String, dynamic> peertubeImportPayload(
        PeerTubeVideo v, PeerTubeAccount acct) =>
    {
      'text': v.displayText,
      'app': 'kickback',
      'imported_from': {
        'platform': 'peertube',
        'account': acct.full,
        'status_id': v.uuid,
        'url': v.url,
        'posted_at': v.publishedAt.toUtc().toIso8601String(),
        'kind': 'video',
        'title': v.title,
        'description': v.description,
        'thumbnail': v.thumbnailUrl,
        'duration': v.durationSeconds,
      },
    };

/// PeerTube video UUIDs already in the local log, read back out of post
/// payloads, so a re-import never doubles a video.
Set<String> importedPeerTubeVideoUuids(
    Iterable<Map<String, dynamic>> payloads) {
  final out = <String>{};
  for (final p in payloads) {
    final src = p['imported_from'];
    if (src is Map && src['platform'] == 'peertube') {
      final id = src['status_id'];
      if (id is String) out.add(id);
    }
  }
  return out;
}

/// A user-readable import failure.
class PeerTubeImportException implements Exception {
  final String message;
  PeerTubeImportException(this.message);
  @override
  String toString() => message;
}

/// The read-only PeerTube API client. Public endpoints only; nothing is
/// ever written to the instance and no credential exists to send. Every
/// call goes to the account's own instance.
class PeerTubeClient {
  final http.Client _http;
  PeerTubeClient([http.Client? client]) : _http = client ?? http.Client();

  /// The public account object for [acct] from its own instance.
  Future<Map<String, dynamic>> lookupAccount(PeerTubeAccount acct) async {
    final uri = Uri.https(
        acct.instance, '/api/v1/accounts/${acct.name}');
    final body = await _get(uri, acct.instance);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['id'] == null) {
      throw PeerTubeImportException(
          'That account did not answer as expected on ${acct.instance}.');
    }
    return decoded;
  }

  /// The account's channels, newest first. A failure here reads as "no
  /// channels": the account description is checked first, and a missing
  /// channel list must not block a claim made in the bio itself.
  Future<List<Map<String, dynamic>>> listChannels(
      PeerTubeAccount acct) async {
    final uri = Uri.https(
        acct.instance, '/api/v1/accounts/${acct.name}/video-channels');
    final body = await _get(uri, acct.instance);
    final decoded = jsonDecode(body);
    final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
    if (data is! List) return [];
    return data.whereType<Map<String, dynamic>>().toList();
  }

  /// The account's most recent public videos, newest first.
  Future<List<PeerTubeVideo>> recentVideos(PeerTubeAccount acct,
      {int limit = kPeerTubeImportLimit}) async {
    final uri = Uri.https(
        acct.instance, '/api/v1/accounts/${acct.name}/videos', {
      'count': '$limit',
      'sort': '-publishedAt',
    });
    final body = await _get(uri, acct.instance);
    final decoded = jsonDecode(body);
    final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
    if (data is! List) {
      throw PeerTubeImportException(
          'The video list did not answer as expected on ${acct.instance}.');
    }
    final out = <PeerTubeVideo>[];
    for (final item in data) {
      if (item is Map<String, dynamic>) {
        final v = PeerTubeVideo.fromJson(item, acct.instance);
        if (v != null) out.add(v);
      }
    }
    return out;
  }

  Future<String> _get(Uri uri, String instance) async {
    final http.Response res;
    try {
      res = await _http.get(uri).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw PeerTubeImportException(
          'Could not reach $instance. Check the connection and the address.');
    }
    if (res.statusCode == 404) {
      throw PeerTubeImportException('No such account on $instance.');
    }
    if (res.statusCode != 200) {
      throw PeerTubeImportException(
          '$instance answered ${res.statusCode}. Try again in a bit.');
    }
    return res.body;
  }
}
