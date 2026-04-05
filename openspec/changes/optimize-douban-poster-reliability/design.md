# Design: Optimize Douban Poster Reliability

## Summary

Keep the current Douban-first product intent for poster matching, but stop treating Douban as a cheap, always-available client-side endpoint. Add persistent lookup caching, a dedicated request client with rate-limit-aware behavior, and optional internal proxy routing so the Douban path behaves more like a resilient metadata provider and less like a raw best-effort HTTP call.

## Current Behavior

`PosterArtworkService.fetchPoster(...)` currently resolves posters in this order:

1. Manual overrides
2. In-memory/title cache and persisted hash match cache
3. Direct Douban suggestion lookup
4. TMDB custom key
5. TMDB built-in key

The Douban portion has a few useful protections already:

- in-flight request coalescing per normalized query
- small LRU in-memory query result cache
- a fixed concurrent request cap
- a simple fixed-duration cooldown after repeated failure

But it still has key weaknesses:

- query cache is session-only and lost on relaunch
- failures are not persisted, so repeated cold starts can replay the same bad traffic pattern
- direct requests use `URLSession.shared`, so the Douban search path is not isolated or centrally configurable
- the failure model is binary and coarse; it does not distinguish short spikes from sustained throttling
- image requests still go directly to `doubanio.com` from the client unless headers happen to be enough

## Reference Patterns

### MoviePilot

- Uses a dedicated `DoubanCache` for normalized metadata lookups and persists it beyond a single process lifetime.
- Has moved Douban APIs toward async request flows and explicit rate-limit handling.
- Routes Douban image URLs through a backend endpoint in the frontend when the URL contains `doubanio.com`.

### StrmAssistant

From the project wiki, the presence of separate “Proxy Server” and “Douban-assisted scraping” capabilities suggests a similar strategy: reduce fragile direct client access and let a helper/proxy layer absorb network variability.

This is an inference from the project’s own documentation structure, not a direct code-level confirmation.

## Proposed Approach

### 1. Add a persistent Douban lookup cache

Introduce a dedicated cache for normalized Douban poster lookup results keyed by:

- normalized primary title
- normalized alternate/English title when available
- year bucket
- inferred media type when available

Cache entries should store at least:

- resolved poster URL
- matched Douban subject id if available
- provider health outcome (`success`, `negative`, `rate_limited`, `network_error`)
- timestamp metadata for TTL decisions

Behavior:

- successful matches get a relatively long TTL
- negative matches get a shorter TTL
- explicit rate-limit outcomes get a short suppression TTL to prevent burst replays

This complements, rather than replaces, the existing hash/title match caches.

### 2. Isolate Douban networking behind a dedicated client

Replace the current direct `URLSession.shared` path with a `DoubanRequestClient` responsible for:

- reusable browser-like headers
- a dedicated `URLSessionConfiguration`
- timeout budgeting
- response classification
- backoff state
- optional internal proxy endpoint rewriting

The client should recognize rate-limit-style failures explicitly and expose structured outcomes instead of returning only “success or empty”.

### 3. Upgrade failure handling from fixed cooldown to provider health

Instead of opening a single fixed cooldown after a small number of failures:

- classify failures as rate-limit, timeout, decode, network, or empty-result
- apply jittered exponential suppression for rate-limit/network failures
- allow success to recover health progressively
- short-circuit Douban early while unhealthy so rows can reach TMDB fallback quickly

This keeps the UI responsive even when Douban is unstable.

### 4. Support optional internal proxy-based routing

Add internal configuration hooks for:

- Douban search proxy base URL
- Douban image proxy base URL

If configured internally:

- suggestion/search requests go through the proxy endpoint instead of directly to `movie.douban.com`
- `doubanio.com` poster URLs are rewritten through the proxy for image loading

If not configured:

- the app continues using direct access with the improved client and cache behavior

This mirrors the operational flexibility seen in projects like MoviePilot without making a backend mandatory or adding a Pro-facing settings surface.

### 5. Preserve the existing fallback chain

Do not remove TMDB fallback. The improved order should still be:

1. local manual override and persisted direct match
2. persistent Douban lookup cache
3. direct or proxied Douban lookup if the provider is healthy enough
4. TMDB custom key
5. TMDB built-in key

The goal is not “always use TMDB first”; it is “make Douban-first viable under real-world limits”.

## Risks and Mitigations

- More state complexity: mitigate by isolating the new logic into a dedicated Douban client/cache type.
- Stale cache results: mitigate with TTLs and explicit invalidation when users manually refresh a poster.
- Proxy-related complexity: mitigate by keeping routing hooks internal and avoiding user-facing settings unless a future product need appears.

## Validation Plan

- Cold launch the app twice with the same set of titles and confirm the second pass reuses persisted Douban lookup results.
- Simulate repeated Douban failures and confirm the app falls through to TMDB without repeated multi-second stalls.
- If an internal proxy URL is configured, confirm search and image requests are rewritten through it.
- Re-run manual poster refresh and confirm it invalidates the relevant Douban cache entry.
