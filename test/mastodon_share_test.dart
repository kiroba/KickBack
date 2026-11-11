import 'package:flutter_test/flutter_test.dart';
import 'package:kickback/mastodon_share.dart';

void main() {
  test('share URL carries the post text and the tester-page link', () {
    final uri = buildMastodonShareUrl('Hello mesh');
    expect(uri.scheme, 'https');
    expect(uri.host, 'mastodon.social');
    expect(uri.path, '/share');
    final text = uri.queryParameters['text']!;
    expect(text, contains('Hello mesh'));
    expect(text, contains('https://kiroba.github.io/The-Omniverse/'));
  });

  test('long posts are clipped so the link survives inside 500 chars', () {
    final uri = buildMastodonShareUrl('x' * 1000);
    final text = uri.queryParameters['text']!;
    expect(text.length, lessThanOrEqualTo(500));
    expect(text, endsWith('https://kiroba.github.io/The-Omniverse/'));
    expect(text, contains('…'));
  });

  test('blank text still shares just the link', () {
    final uri = buildMastodonShareUrl('   ');
    expect(uri.queryParameters['text'],
        contains('https://kiroba.github.io/The-Omniverse/'));
  });
}
