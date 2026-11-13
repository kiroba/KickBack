// Tests for the Mastodon -> KickBack import (lib/mastodon_import.dart):
// address parsing, the ownership-code check, HTML -> plain text, status
// filtering, payload mapping and dedupe. The status fixture mirrors the
// real shape of a public post on mastodon.social.
import 'package:flutter_test/flutter_test.dart';

import 'package:kickback/mastodon_import.dart';

Map<String, dynamic> _statusJson({
  String id = '117610848183724782',
  Object? reblog,
  Object? inReplyToId,
  String visibility = 'public',
  String content =
      '<p>hello from the kickback</p><p><a href="https://kiroba.github.io/The-Omniverse/" target="_blank" rel="nofollow noopener" translate="no"><span class="invisible">https://</span><span class="">kiroba.github.io/The-Omniverse/</span><span class="invisible"></span></a></p>',
}) =>
    {
      'id': id,
      'created_at': '2026-11-13T19:45:23.898Z',
      'in_reply_to_id': inReplyToId,
      'visibility': visibility,
      'url': 'https://mastodon.social/@kirobash/$id',
      'content': content,
      'reblog': reblog,
    };

void main() {
  group('parseMastodonAcct', () {
    test('full address', () {
      final a = parseMastodonAcct('@kirobash@mastodon.social')!;
      expect(a.username, 'kirobash');
      expect(a.instance, 'mastodon.social');
      expect(a.full, '@kirobash@mastodon.social');
    });

    test('no leading @, bare user on the default instance', () {
      expect(parseMastodonAcct('kirobash@mastodon.social')!.instance,
          'mastodon.social');
      final bare = parseMastodonAcct('@kirobash')!;
      expect(bare.username, 'kirobash');
      expect(bare.instance, kDefaultMastodonInstance);
    });

    test('profile URL', () {
      final a = parseMastodonAcct('https://mastodon.social/@kirobash')!;
      expect(a.username, 'kirobash');
      expect(a.instance, 'mastodon.social');
      final other = parseMastodonAcct('https://hachyderm.io/@someone')!;
      expect(other.instance, 'hachyderm.io');
    });

    test('junk is rejected', () {
      expect(parseMastodonAcct(''), isNull);
      expect(parseMastodonAcct('hello world'), isNull);
      expect(parseMastodonAcct('@@double'), isNull);
      expect(parseMastodonAcct('user@nodot'), isNull);
      expect(parseMastodonAcct('@user@a@b.social'), isNull);
    });
  });

  group('ownership code', () {
    const pub =
        'a2d1c74f0000000000000000000000000000000000000000000000000000272a';
    test('code is the first 8 hex of the public key', () {
      expect(mastodonVerifyCode(pub), 'omni-verify-a2d1c74f');
    });

    test('found in the bio', () {
      final account = {
        'note': '<p>Average human. omni-verify-a2d1c74f</p>',
        'fields': <dynamic>[],
      };
      expect(mastodonAccountClaimsCode(account, 'omni-verify-a2d1c74f'),
          isTrue);
    });

    test('found in a profile field', () {
      final account = {
        'note': '<p>Average human.</p>',
        'fields': [
          {'name': 'KickBack', 'value': '<p>omni-verify-a2d1c74f</p>'},
        ],
      };
      expect(mastodonAccountClaimsCode(account, 'omni-verify-a2d1c74f'),
          isTrue);
    });

    test('absent means not claimed', () {
      final account = {
        'note': '<p>Average human with well above average ideas.</p>',
        'fields': <dynamic>[],
      };
      expect(mastodonAccountClaimsCode(account, 'omni-verify-a2d1c74f'),
          isFalse);
    });
  });

  group('mastodonHtmlToText', () {
    test('paragraphs become blank lines and link URLs come back whole', () {
      final s = MastodonStatus.fromJson(_statusJson())!;
      expect(s.text,
          'hello from the kickback\n\nhttps://kiroba.github.io/The-Omniverse/');
    });

    test('entities are unescaped', () {
      expect(mastodonHtmlToText('<p>Tom &amp; Jerry &lt;3 &#8212; &#x2019;tis</p>'),
          'Tom & Jerry <3 — ’tis');
    });

    test('breaks become single newlines', () {
      expect(mastodonHtmlToText('<p>one<br>two</p>'), 'one\ntwo');
    });
  });

  group('MastodonStatus.fromJson filtering', () {
    test('an original public post imports', () {
      final s = MastodonStatus.fromJson(_statusJson())!;
      expect(s.id, '117610848183724782');
      expect(s.url, 'https://mastodon.social/@kirobash/117610848183724782');
      expect(s.createdAt.toUtc().hour, 19);
    });

    test('boosts, replies and non-public posts do not', () {
      expect(
          MastodonStatus.fromJson(_statusJson(reblog: {'id': '1'})), isNull);
      expect(
          MastodonStatus.fromJson(_statusJson(inReplyToId: '99')), isNull);
      expect(MastodonStatus.fromJson(_statusJson(visibility: 'unlisted')),
          isNull);
      expect(MastodonStatus.fromJson(_statusJson(visibility: 'private')),
          isNull);
    });

    test('a post with no text left after stripping does not import', () {
      expect(MastodonStatus.fromJson(_statusJson(content: '<p>  </p>')),
          isNull);
    });
  });

  group('payload + dedupe', () {
    test('the payload carries text and signed provenance', () {
      final s = MastodonStatus.fromJson(_statusJson())!;
      final p = mastodonImportPayload(
          s, const MastodonAcct('kirobash', 'mastodon.social'));
      expect(p['text'], startsWith('hello from the kickback'));
      expect(p['app'], 'kickback');
      final src = p['imported_from'] as Map;
      expect(src['platform'], 'mastodon');
      expect(src['account'], '@kirobash@mastodon.social');
      expect(src['status_id'], '117610848183724782');
      expect(src['url'],
          'https://mastodon.social/@kirobash/117610848183724782');
      expect(src['posted_at'], '2026-11-13T19:45:23.898Z');
    });

    test('dedupe reads status ids back out of stored payloads', () {
      final s = MastodonStatus.fromJson(_statusJson())!;
      final payloads = <Map<String, dynamic>>[
        {'text': 'a local post', 'app': 'kickback'},
        mastodonImportPayload(
            s, const MastodonAcct('kirobash', 'mastodon.social')),
        {
          'text': 'x',
          'imported_from': {'platform': 'bluesky', 'status_id': 'zzz'},
        },
      ];
      expect(importedMastodonStatusIds(payloads),
          {'117610848183724782'});
    });
  });
}
