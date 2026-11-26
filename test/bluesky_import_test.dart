// Tests for the Bluesky -> KickBack import (lib/bluesky_import.dart):
// handle parsing, the ownership-code check, feed-item filtering, payload
// mapping and dedupe. The feed fixture mirrors the real shape of a public
// post on public.api.bsky.app.
import 'package:flutter_test/flutter_test.dart';

import 'package:kickback/bluesky_import.dart';

Map<String, dynamic> _feedItem({
  String uri =
      'at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.post/3n2xthjwiac22',
  Object? reason,
  Object? reply,
  String type = 'app.bsky.feed.post',
  String text = 'hello from the kickback',
  String createdAt = '2026-11-26T15:28:00.000Z',
}) =>
    {
      'post': {
        'uri': uri,
        'cid':
            'bafyreicahfeh6pb3htyefflu7fcjjle7pqetqypmx2ko3ymvr6hbo2fi3e',
        'author': {
          'did': 'did:plc:z72i7hdynmk6r22z27h6tvur',
          'handle': 'kiroba.bsky.social',
        },
        'record': {
          '\$type': type,
          'createdAt': createdAt,
          if (reply != null) 'reply': reply,
          'text': text,
        },
      },
      if (reason != null) 'reason': reason,
    };

void main() {
  group('parseBlueskyHandle', () {
    test('full handle', () {
      final h = parseBlueskyHandle('kiroba.bsky.social')!;
      expect(h.handle, 'kiroba.bsky.social');
      expect(h.full, '@kiroba.bsky.social');
    });

    test('leading @ and custom domains', () {
      expect(parseBlueskyHandle('@kiroba.bsky.social')!.handle,
          'kiroba.bsky.social');
      expect(parseBlueskyHandle('kiroba.example.com')!.handle,
          'kiroba.example.com');
    });

    test('profile URL', () {
      final h = parseBlueskyHandle(
          'https://bsky.app/profile/kiroba.bsky.social')!;
      expect(h.handle, 'kiroba.bsky.social');
    });

    test('junk is rejected', () {
      expect(parseBlueskyHandle(''), isNull);
      expect(parseBlueskyHandle('hello world'), isNull);
      expect(parseBlueskyHandle('kiroba'), isNull);
      expect(parseBlueskyHandle('did:plc:z72i7hdynmk6r22z27h6tvur'), isNull);
      expect(parseBlueskyHandle('@user@a@b.social'), isNull);
    });
  });

  group('ownership code', () {
    const pub =
        'a2d1c74f0000000000000000000000000000000000000000000000000000272a';
    test('code is the first 8 hex of the public key', () {
      expect(blueskyVerifyCode(pub), 'omni-verify-a2d1c74f');
    });

    test('found in the bio', () {
      final profile = {
        'did': 'did:plc:z72i7hdynmk6r22z27h6tvur',
        'handle': 'kiroba.bsky.social',
        'description': 'Average human. omni-verify-a2d1c74f',
      };
      expect(blueskyProfileClaimsCode(profile, 'omni-verify-a2d1c74f'),
          isTrue);
    });

    test('absent means not claimed', () {
      final profile = {
        'did': 'did:plc:z72i7hdynmk6r22z27h6tvur',
        'handle': 'kiroba.bsky.social',
        'description': 'Average human with well above average ideas.',
      };
      expect(blueskyProfileClaimsCode(profile, 'omni-verify-a2d1c74f'),
          isFalse);
    });
  });

  group('BlueskyPost.fromFeedItem filtering', () {
    test('an original public post imports', () {
      final p = BlueskyPost.fromFeedItem(_feedItem(), 'kiroba.bsky.social')!;
      expect(p.uri,
          'at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.post/3n2xthjwiac22');
      expect(p.url,
          'https://bsky.app/profile/kiroba.bsky.social/post/3n2xthjwiac22');
      expect(p.text, 'hello from the kickback');
      expect(p.createdAt.toUtc().hour, 15);
    });

    test('reposts, replies and non-posts do not', () {
      expect(
          BlueskyPost.fromFeedItem(
              _feedItem(reason: {
                '\$type': 'app.bsky.feed.defs#reasonRepost',
                'by': {'did': 'did:plc:other'},
                'indexedAt': '2026-11-26T15:30:00.000Z',
              }),
              'kiroba.bsky.social'),
          isNull);
      expect(
          BlueskyPost.fromFeedItem(
              _feedItem(reply: {
                'root': {'uri': 'at://did:plc:x/app.bsky.feed.post/abc'},
                'parent': {'uri': 'at://did:plc:x/app.bsky.feed.post/abc'},
              }),
              'kiroba.bsky.social'),
          isNull);
      expect(
          BlueskyPost.fromFeedItem(
              _feedItem(type: 'app.bsky.feed.threadgate'),
              'kiroba.bsky.social'),
          isNull);
    });

    test('a post with no text does not import', () {
      expect(
          BlueskyPost.fromFeedItem(
              _feedItem(text: '   '), 'kiroba.bsky.social'),
          isNull);
    });
  });

  group('payload + dedupe', () {
    test('the payload carries text and signed provenance', () {
      final p = BlueskyPost.fromFeedItem(_feedItem(), 'kiroba.bsky.social')!;
      final payload = blueskyImportPayload(
          p, const BlueskyHandle('kiroba.bsky.social'));
      expect(payload['text'], 'hello from the kickback');
      expect(payload['app'], 'kickback');
      final src = payload['imported_from'] as Map;
      expect(src['platform'], 'bluesky');
      expect(src['account'], '@kiroba.bsky.social');
      expect(src['status_id'],
          'at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.post/3n2xthjwiac22');
      expect(src['url'],
          'https://bsky.app/profile/kiroba.bsky.social/post/3n2xthjwiac22');
      expect(src['posted_at'], '2026-11-26T15:28:00.000Z');
    });

    test('dedupe reads post URIs back out of stored payloads', () {
      final p = BlueskyPost.fromFeedItem(_feedItem(), 'kiroba.bsky.social')!;
      final payloads = <Map<String, dynamic>>[
        {'text': 'a local post', 'app': 'kickback'},
        blueskyImportPayload(p, const BlueskyHandle('kiroba.bsky.social')),
        {
          'text': 'x',
          'imported_from': {'platform': 'mastodon', 'status_id': 'zzz'},
        },
      ];
      expect(importedBlueskyPostUris(payloads), {
        'at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.post/3n2xthjwiac22'
      });
    });
  });
}
