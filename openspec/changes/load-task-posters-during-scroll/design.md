# Design: Load Task Posters During Scroll

## Summary

Remove the transfers poster queue's scroll-time pause so that visible rows can start poster resolution immediately. Keep the current queue depth, cache fast paths, and non-poster scroll throttling intact.

## Current Behavior

- `TransfersHostedRowContent` calls `posterStore.resolveIfNeeded(...)` when a row appears.
- `TransfersPosterStore.resolveIfNeeded(...)` enqueues poster work for rows without a cached result.
- `TransfersPosterStore.pumpQueue()` exits early while `isScrolling == true`, so queued requests do not start until scrolling ends.
- `TransfersViewModel.handleScrollActivityChanged(...)` also defers list recomputation and refresh-related work until scrolling settles.

The last item is still useful. The issue is that poster loading was coupled to the same scroll gate even though it already has its own lightweight backpressure.

## Proposed Approach

### 1. Decouple poster loading from scroll activity

- Stop using scroll state to pause poster queue execution.
- Allow `pumpQueue()` to start requests whenever poster rendering is enabled and a `ModelContext` is available.
- Keep row-driven enqueue behavior unchanged so work still starts from visible content rather than from the whole dataset.

### 2. Keep existing backpressure and prioritization

- Keep `maxConcurrentRequests = 2`.
- Keep the current cache fast path so previously resolved posters still return immediately.
- Keep duplicate-request suppression based on torrent hash.
- Keep the current LIFO queue behavior so newly visible rows stay prioritized during fast scrolling.

### 3. Preserve non-poster scroll protections

- Keep `TransfersViewModel` scroll handling for deferred filter recomputation and refresh suspension.
- Keep the table view's scroll callbacks because they still serve non-poster behaviors.
- Treat poster loading as independent from expensive list mutation work.

## Alternatives Considered

### Keep the current pause-until-idle behavior

This minimizes work during motion, but it causes visible lag and makes poster loading feel broken when users browse long lists quickly.

### Preload posters beyond visible rows

This would hide some latency, but it would also increase unnecessary network and parsing work and is not required to fix the current UX issue.

### Allow loading only during drag but not deceleration

This removes part of the delay, but users would still see placeholders during fling/deceleration, which is one of the most common list browsing patterns.

## Risks and Mitigations

- More work during scrolling: mitigated by the existing concurrency cap and cache reuse.
- Request churn while rapidly moving through rows: mitigated by duplicate suppression and visible-row-driven enqueueing.
- Visual instability: keep current non-fade image rendering and poster preheating behavior.

## Validation Plan

- Slow drag through a long transfers list and confirm posters begin resolving before lifting the finger.
- Fast fling and confirm visible rows can fill in during deceleration.
- Confirm search/filter refresh behavior still waits for scroll settle where intended.
- Compare poster diagnostics before and after if instrumentation is enabled.
