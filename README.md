# KickBack

The KickBack social network for The Omniverse. Split out of [kiroba/The-Omniverse](https://github.com/kiroba/The-Omniverse) with its git history (Oct 30 2026).

## Status (Nov 16, 2026)

- **Identity transfer import — live.** Carry your @handle Halo identity in from LPE with a transfer code and sign as that identity (PR #9; the import lives in the live settings sheet since PR #14, Nov 14, 2026).
- **Mastodon import — live.** Bring your own public Mastodon posts back into KickBack (PR #13, Nov 13, 2026), and share a post outward to Mastodon via web intent (PR #10).
- **Image posts and mutual friends — MVP in progress.** Images are cached locally, uploaded to the current Omni-Daemon by SHA-256, and referenced from signed posts. Friend requests and acceptances are signed `KICKBACK_FRIEND` events and appear in the Friends sheet.

## In the works (Nov 30, 2026 cycle — not shipped)

Remove the top-bar update button, video (short clips first-class; long video later via asset streaming), profile discovery, and a community layer built for the mesh — relay circles, where membership is a mutual add and your node carries for the group.

## Build
```
flutter pub get
flutter build apk --release --target-platform android-arm64
```
Shared code comes from [Omni-Core-UI](https://github.com/kiroba/Omni-Core-UI), pinned by tag in `pubspec.yaml`.

CI here makes test builds (debug key). Signed releases still come from the monorepo's `release.yml` until release orchestration moves.

`design/` holds NotebookLM design screens (UI only, not wired yet). `tool/build_multi_app_suite.py` is the old generator, kept for reference.
