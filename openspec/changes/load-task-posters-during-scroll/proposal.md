# Proposal: Load Task Posters During Scroll

## Why

The transfers list currently delays new poster fetches until scrolling fully settles. Rows that become visible during drag or deceleration keep showing placeholders even though the user is already looking at them.

This makes the poster experience feel slower than the rest of the app and out of step with common mobile list behavior, where visible images usually begin loading while the list is still moving.

## What Changes

- Start resolving task posters as soon as a row becomes visible, even if the list is actively scrolling.
- Keep the existing concurrency cap, cache reuse, and duplicate-request suppression so the change improves responsiveness without turning poster loading into an unbounded background workload.
- Preserve current scroll-time protections for expensive list recomputation and refresh work. This change only affects poster fetching.

## Scope

### In Scope

- Transfers poster queue behavior
- Visible-row poster loading while dragging or decelerating
- Validation that scrolling remains smooth on long lists

### Out of Scope

- Preloading posters for the entire dataset
- Reworking list virtualization or row layout
- Changing poster providers, matching rules, or cache schema

## Success Criteria

- A visible row can begin poster resolution before the user stops scrolling.
- Poster placeholders no longer wait for drag/deceleration to finish before the queue starts work.
- Transfers list scrolling remains acceptably smooth with posters enabled.
