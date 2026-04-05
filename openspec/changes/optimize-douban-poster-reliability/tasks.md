# Tasks: Optimize Douban Poster Reliability

## 1. Add Persistent Douban Lookup State

- [x] 1.1 Introduce a dedicated persistent cache for normalized Douban lookup results and failure outcomes.
- [x] 1.2 Wire poster refresh/invalidation flows so manual refresh can clear the relevant Douban cache entry.

## 2. Refactor Douban Networking

- [x] 2.1 Extract direct Douban search logic into a dedicated request client instead of using `URLSession.shared`.
- [x] 2.2 Add structured response classification for success, negative result, rate limit, timeout, decode failure, and network error.
- [x] 2.3 Replace the fixed cooldown logic with provider-health suppression and progressive recovery.

## 3. Add Internal Proxy Support

- [x] 3.1 Add internal configuration hooks for Douban search proxy and Douban image proxy.
- [x] 3.2 Rewrite Douban search and image URLs through the configured proxy when present.
- [x] 3.3 Keep proxy routing out of the user-facing Pro settings UI.

## 4. Preserve Poster Pipeline Behavior

- [x] 4.1 Keep manual overrides and existing TMDB fallback behavior intact.
- [x] 4.2 Ensure the improved Douban path still prefers cached/persisted results before new network work.

## 5. Verify Reliability

- [x] 5.1 Validate repeated cold-start lookups reuse persisted Douban results.
- [x] 5.2 Validate rate-limited Douban traffic falls through quickly to TMDB.
- [x] 5.3 Validate proxy-based routing works when internally configured and is inert when not configured.
