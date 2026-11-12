/// First outward link from KickBack to another platform: Mastodon.
///
/// No API key, no OAuth, no account stored in the app, no hosted service.
/// The share intent opens in the user's external browser and they post from
/// their own Mastodon account. What leaves the Omniverse is the post text
/// plus a link back to the tester page, so a public post can point people
/// back at the apps.
///
/// Pure Dart (no Flutter imports) so the URL building is unit-testable.

/// Where a shared post points back to.
const String kTesterPageUrl = 'https://kiroba.github.io/The-Omniverse/';

/// Mastodon's character limit; the link back is reserved first so it
/// always survives, even for a long post.
const int kMastodonCharLimit = 500;

/// Builds the Mastodon web share URL for a post: the post text plus a link
/// back to the tester page. Long posts are clipped with an ellipsis so the
/// shared text (post + link) never exceeds Mastodon's limit.
Uri buildMastodonShareUrl(String text, {String link = kTesterPageUrl}) {
  final suffix = '\n\n$link';
  var body = text.trim();
  final room = kMastodonCharLimit - suffix.length;
  if (body.length > room) {
    body = '${body.substring(0, room - 1)}…';
  }
  return Uri.parse('https://mastodon.social/share')
      .replace(queryParameters: {'text': '$body$suffix'});
}
