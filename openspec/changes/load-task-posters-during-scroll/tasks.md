# Tasks: Load Task Posters During Scroll

## 1. Update Poster Queue Behavior

- [x] 1.1 Remove scroll-state gating from `TransfersPosterStore` so poster requests can start immediately after enqueue.
- [x] 1.2 Keep concurrency limits, cache hits, duplicate suppression, and current visible-row prioritization intact.

## 2. Preserve Existing Scroll-Time Protections

- [x] 2.1 Ensure `TransfersViewModel` still defers expensive list recomputation and refresh work while the list is scrolling.
- [x] 2.2 Keep `TransfersListView` scroll activity reporting for non-poster behaviors.

## 3. Verify UX and Performance

- [ ] 3.1 Manually test slow drag with posters enabled.
- [ ] 3.2 Manually test fast deceleration with posters enabled.
- [ ] 3.3 Confirm visible rows no longer wait for scroll stop before poster loading begins.
- [ ] 3.4 Confirm no obvious scrolling hitching or placeholder regression on long lists.
