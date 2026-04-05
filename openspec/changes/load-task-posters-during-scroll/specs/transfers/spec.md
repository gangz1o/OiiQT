# Transfers Specification Delta

## ADDED Requirements

### Requirement: Visible task rows start poster loading during scroll

When poster rendering is enabled, the transfers list shall start resolving poster artwork for a task row as soon as that row becomes visible, even if the list is actively dragging or decelerating.

#### Scenario: Row becomes visible during drag

- **GIVEN** poster rendering is enabled
- **AND** the user is dragging the transfers list
- **WHEN** a task row becomes visible
- **THEN** the app starts poster resolution for that row without waiting for scrolling to stop

#### Scenario: Row becomes visible during deceleration

- **GIVEN** poster rendering is enabled
- **AND** the transfers list is decelerating after a fling
- **WHEN** a task row becomes visible
- **THEN** the app starts poster resolution for that row during deceleration

### Requirement: Poster loading keeps queue backpressure

The transfers list shall keep poster loading bounded while allowing visible rows to load during scroll.

#### Scenario: Multiple rows appear quickly

- **GIVEN** several task rows become visible in quick succession
- **WHEN** poster requests are enqueued
- **THEN** the app limits concurrent poster work using the existing queue policy
- **AND** newly visible rows remain eligible to start without waiting for scrolling to stop

### Requirement: Scroll-time list recomputation remains deferred

Allowing poster loading during scroll shall not force expensive list recomputation to run during scroll.

#### Scenario: Posters resolve while list recomputation stays deferred

- **GIVEN** the transfers list is actively scrolling
- **WHEN** poster requests start for visible rows
- **THEN** poster loading may proceed
- **AND** expensive filter or refresh recomputation may still wait until scrolling settles
