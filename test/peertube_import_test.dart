// Tests for the PeerTube -> KickBack import (lib/peertube_import.dart):
// account parsing, the ownership-code check, video filtering, payload
// mapping and dedupe. The video fixture mirrors the real shape of a
// public video on a PeerTube instance (verified live against tilvids.com
// Nov 26, 2026).
import 'package:flutter_test/flutter_test.dart';

import 'package:kickback/peertube_import.dart';

Map<String, dynamic> _video({
  String uuid = '649ed903-3bd8-4fb1-b993-4cd0d0498c83',
  String url =
      'https://tilvids.com/videos/watch/649ed903-3bd8-4fb1-b993-4cd0d0498c83',
  String name = 'Happy Thanksgiving! A message from me, to you.',
  String description = 'Today I want to thank every one of you.',
  int privacyId = 1,
  int? duration = 51,
  String publishedAt = '2026-11-26T13:23:19.344Z',
}) =>
    {
      'id': 440941,
      'uuid': uuid,
      'shortUUID': 'dqDRZSBKHLnn2Nhomm55iZ',
      'url': url,
      'name': name,
      'description': description,
      'privacy': {'id': privacyId, 'label': privacyId == 1 ? 'Public' : 'Unlisted'},
      'nsfw': false,
      'duration': duration,
      'thumbnailPath':
          '/lazy-static/thumbnails/7bceff78-cae8-414b-9a9c-d9d4a5ae89f5.jpg',
      'thumbnails': [
        {
          'height': 1080,
          'width': 1920,
          'aspectRatio': '16:9',
          'fileUrl':
              'https://tilvids.com/lazy-static/thumbnails/c87f65fd-011a-4db5-adb2-af41c0f4902b.jpg',
        },
        {
          'height': 720,
          'width': 1280,
          'aspectRatio': '16:9',
          'fileUrl':
              'https://tilvids.com/lazy-static/thumbnails/673f5a76-3cbb-486c-b98c-e33f11980572.jpg',
        },
        {
          'height': 157,
          'width': 280,
          'aspectRatio': '16:9',
          'fileUrl':
              'https://tilvids.com/lazy-static/thumbnails/7bceff78-cae8-414b-9a9c-d9d4a5ae89f5.jpg',
        },
      ],
      'createdAt': '2026-11-26T13:23:03.208Z',
      'publishedAt': publishedAt,
      'account': {
        'name': 'therealjimbbq',
        'displayName': 'The Healthy Pitmaster',
        'url': 'https://tilvids.com/accounts/therealjimbbq',
        'host': 'tilvids.com',
      },
      'channel': {
        'name': 'therealjimbbq_channel',
        'displayName': 'The Healthy Pitmaster',
        'url': 'https://tilvids.com/video-channels/therealjimbbq_channel',
        'host': 'tilvids.com',
      },
    };

void main() {
  group('parsePeerTubeAccount', () {
    test('full address', () {
      final a = parsePeerTubeAccount('therealjimbbq@tilvids.com')!;
      expect(a.name, 'therealjimbbq');
      expect(a.instance, 'tilvids.com');
      expect(a.full, 'therealjimbbq@tilvids.com');
    });

    test('leading @ and account URL', () {
      expect(parsePeerTubeAccount('@therealjimbbq@tilvids.com')!.name,
          'therealjimbbq');
      final a = parsePeerTubeAccount(
          'https://tilvids.com/accounts/therealjimbbq')!;
      expect(a.name, 'therealjimbbq');
      expect(a.instance, 'tilvids.com');
    });

    test('bare name has no instance to default to', () {
      expect(parsePeerTubeAccount('therealjimbbq'), isNull);
      expect(parsePeerTubeAccount('kiroba'), isNull);
    });

    test('channel URLs are not account addresses', () {
      expect(
          parsePeerTubeAccount(
              'https://tilvids.com/video-channels/therealjimbbq_channel'),
          isNull);
    });

    test('junk is rejected', () {
      expect(parsePeerTubeAccount(''), isNull);
      expect(parsePeerTubeAccount('hello world'), isNull);
      expect(parsePeerTubeAccount('user@a@b.com'), isNull);
      expect(parsePeerTubeAccount('user@notahost'), isNull);
      expect(parsePeerTubeAccount('https://tilvids.com/videos/watch/abc'),
          isNull);
    });
  });

  group('ownership code', () {
    const pub =
        'a2d1c74f0000000000000000000000000000000000000000000000000000272a';
    test('code is the first 8 hex of the public key', () {
      expect(peertubeVerifyCode(pub), 'omni-verify-a2d1c74f');
    });

    test('found in the account description', () {
      final account = {
        'name': 'therealjimbbq',
        'description': 'BBQ cook. omni-verify-a2d1c74f',
      };
      expect(peertubeAccountClaimsCode(account, const [], 'omni-verify-a2d1c74f'),
          isTrue);
    });

    test('found in a channel description', () {
      final account = {
        'name': 'therealjimbbq',
        'description': 'BBQ cook.',
      };
      final channels = [
        {
          'name': 'therealjimbbq_channel',
          'description': 'The channel. omni-verify-a2d1c74f',
        },
      ];
      expect(peertubeAccountClaimsCode(account, channels, 'omni-verify-a2d1c74f'),
          isTrue);
    });

    test('absent means not claimed', () {
      final account = {
        'name': 'therealjimbbq',
        'description': 'BBQ cook.',
      };
      expect(peertubeAccountClaimsCode(account, const [], 'omni-verify-a2d1c74f'),
          isFalse);
    });
  });

  group('PeerTubeVideo.fromJson filtering', () {
    test('a public video imports', () {
      final v = PeerTubeVideo.fromJson(_video(), 'tilvids.com')!;
      expect(v.uuid, '649ed903-3bd8-4fb1-b993-4cd0d0498c83');
      expect(v.url,
          'https://tilvids.com/videos/watch/649ed903-3bd8-4fb1-b993-4cd0d0498c83');
      expect(v.title, 'Happy Thanksgiving! A message from me, to you.');
      expect(v.description, 'Today I want to thank every one of you.');
      expect(v.thumbnailUrl,
          'https://tilvids.com/lazy-static/thumbnails/673f5a76-3cbb-486c-b98c-e33f11980572.jpg');
      expect(v.durationSeconds, 51);
      expect(v.publishedAt.toUtc().hour, 13);
    });

    test('the 1280-wide still wins over the bigger one', () {
      final v = PeerTubeVideo.fromJson(_video(), 'tilvids.com')!;
      expect(v.thumbnailUrl, contains('673f5a76'));
    });

    test('unlisted and private videos do not', () {
      expect(PeerTubeVideo.fromJson(_video(privacyId: 2), 'tilvids.com'),
          isNull);
      expect(PeerTubeVideo.fromJson(_video(privacyId: 3), 'tilvids.com'),
          isNull);
    });

    test('a video with no title, uuid or time does not import', () {
      expect(PeerTubeVideo.fromJson(_video(name: '   '), 'tilvids.com'),
          isNull);
      expect(PeerTubeVideo.fromJson(_video(uuid: ''), 'tilvids.com'), isNull);
      expect(
          PeerTubeVideo.fromJson(_video(publishedAt: 'not-a-date'),
              'tilvids.com'),
          isNull);
    });
  });

  group('payload + dedupe', () {
    test('the payload carries the video and signed provenance', () {
      final v = PeerTubeVideo.fromJson(_video(), 'tilvids.com')!;
      final payload = peertubeImportPayload(
          v, const PeerTubeAccount('therealjimbbq', 'tilvids.com'));
      expect(payload['text'],
          'Happy Thanksgiving! A message from me, to you.\n\nToday I want to thank every one of you.');
      expect(payload['app'], 'kickback');
      final src = payload['imported_from'] as Map;
      expect(src['platform'], 'peertube');
      expect(src['account'], 'therealjimbbq@tilvids.com');
      expect(src['status_id'], '649ed903-3bd8-4fb1-b993-4cd0d0498c83');
      expect(src['url'],
          'https://tilvids.com/videos/watch/649ed903-3bd8-4fb1-b993-4cd0d0498c83');
      expect(src['posted_at'], '2026-11-26T13:23:19.344Z');
      expect(src['kind'], 'video');
      expect(src['title'], 'Happy Thanksgiving! A message from me, to you.');
      expect(src['description'], 'Today I want to thank every one of you.');
      expect(src['thumbnail'], contains('673f5a76'));
      expect(src['duration'], 51);
    });

    test('a video with no description carries just the title', () {
      final v =
          PeerTubeVideo.fromJson(_video(description: ''), 'tilvids.com')!;
      final payload = peertubeImportPayload(
          v, const PeerTubeAccount('therealjimbbq', 'tilvids.com'));
      expect(payload['text'], 'Happy Thanksgiving! A message from me, to you.');
    });

    test('dedupe reads video UUIDs back out of stored payloads', () {
      final v = PeerTubeVideo.fromJson(_video(), 'tilvids.com')!;
      final payloads = <Map<String, dynamic>>[
        {'text': 'a local post', 'app': 'kickback'},
        peertubeImportPayload(
            v, const PeerTubeAccount('therealjimbbq', 'tilvids.com')),
        {
          'text': 'x',
          'imported_from': {'platform': 'bluesky', 'status_id': 'at://zzz'},
        },
      ];
      expect(importedPeerTubeVideoUuids(payloads),
          {'649ed903-3bd8-4fb1-b993-4cd0d0498c83'});
    });
  });
}
