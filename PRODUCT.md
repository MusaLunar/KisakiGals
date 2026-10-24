# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

> Flutter Windows desktop app (Windows 10 1809+). Recorded as `web` because no native-iOS/Android design language applies; the design target is a desktop pointer-and-keyboard surface rendered by Flutter, not a browser.

## Users

A single Galgame (visual novel) player managing a personal collection on their own Windows PC. The app usually lives in the system tray tracking playtime; the user opens it occasionally, typically in the evening or idle time, to pick something to play, continue a recent title, or look back at playtime statistics. (Confirmed.)

## Product Purpose

Keep a personal visual-novel collection, launch games in one action, and record how long each one was actually played, so the player can remember and revisit the works they love. Success: opening the app gets the user into a game, or to the answer they wanted about their play history, within seconds.

## Positioning

Local-first, single-folder portable manager that combines second-level process playtime tracking, multi-source metadata merging (9 sources), Locale Emulator launching and automatic save backup for Galgames specifically. All data stays beside the exe.

## Operating Context

- Tray-resident: playtime keeps counting while minimized; the title bar and detail page show the live session timer.
- Main surfaces: Home (week/month/total overview, recent games, timeline, recommendations), Library (2:3 cover grid / compact list, filter sidebar, batch mode), Game detail (playtime stats, 30-day trend, ratings, tags, summary, sources, launch), Discover (VNDB/Bangumi rankings + resource-site aggregation), Stats (info / ratings / summary, heatmaps, word cloud), AI assistant, Add game (drag exe/folder, multi-source scrape), Settings.
- Covers and CG art are the primary visual content; many covers can be NSFW and are blurred/placeholdered per setting.

## Capabilities and Constraints

- All business features, data flow and stored data must be preserved. Page layout and information hierarchy may be rearranged (e.g. Home and Detail recomposed). (Confirmed.)
- Built with Flutter 3.x + Riverpod; bundled font Noto Sans SC (400/500/700); Chinese UI copy.
- Window minimum size 1080x680, default 1280 wide; custom title bar via window_manager.

## Brand Commitments

- Name: KisakiGals. Tagline: 「无论何时，都想与她们再次相见。」 Logo: `assets/logo/`.
- No visual direction was pinned by the user for this redesign.

## Evidence on Hand

- Real user library data lives only on the user's machine; screenshots in `docs/screens/` show prior UI. No testimonials, metrics or press exist and none may be fabricated.

## Product Principles

1. Get the player into the game: launch / continue is always one action away.
2. Covers lead: the works are the content, interface chrome recedes.
3. Memory over metrics: playtime and history are presented as recollection, not as a dashboard to optimize.
4. Never lose data: every redesign preserves storage, migration and backup behavior.
