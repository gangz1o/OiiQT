# Proposal: Optimize Douban Poster Reliability

## Why

The transfers poster pipeline currently prefers Douban lookups before TMDB network fallback, but the Douban path is fragile under rate limiting.

Today OiiQT performs direct client-side requests to `movie.douban.com/j/subject_suggest`, keeps only a small in-memory query cache for the current session, and opens a fixed cooldown after repeated failures. This means a burst of new titles can quickly push the app into a state where Douban is effectively unavailable for several minutes, making poster loading feel inconsistent.

Reference projects appear to be faster not because they simply hit Douban harder, but because they reduce repeated direct requests:

- MoviePilot maintains a dedicated Douban cache layer for normalized metadata matches.
- MoviePilot has moved large parts of its Douban stack to async request paths with rate-limit-aware handling.
- MoviePilot’s frontend routes Douban image URLs through a backend image endpoint instead of always loading `doubanio.com` directly from the client.
- StrmAssistant publicly exposes both “Proxy Server” and “Douban-assisted scraping” capabilities, which strongly suggests the project also reduces direct client-to-Douban dependence.

## What Changes

- Introduce a reliability-oriented Douban lookup layer for poster matching.
- Persist successful and failed Douban lookup results across app launches so repeated titles do not re-trigger the same direct requests.
- Replace the current fixed failure cooldown with a more expressive health model that reacts faster to Douban throttling and recovers more gracefully.
- Keep optional proxy-capable request paths available for Douban search and image loading, but treat them as internal wiring rather than a user-facing Pro setting.
- Keep TMDB fallback intact, but make the Douban-first path cheaper, more cache-friendly, and less likely to collapse under bursts.

## Scope

### In Scope

- Transfers poster lookup strategy
- Douban request client behavior
- Persistent Douban query caching
- Rate-limit detection, backoff, and fallback behavior
- Internal proxy routing hooks for Douban search/image traffic

### Out of Scope

- Replacing Douban as a source entirely
- Reworking TMDB matching logic
- Building a mandatory bundled backend service
- Changing manual poster override behavior

## Success Criteria

- Repeated poster lookups for the same or similar titles reuse persisted Douban match results instead of re-querying Douban every session.
- When Douban starts throttling, OiiQT skips wasteful repeated retries and falls back quickly.
- If an internal proxy-capable endpoint is supplied, the app can route Douban traffic through it without exposing extra end-user configuration.
- Poster loading remains compatible with the existing TMDB fallback path and manual override flow.
