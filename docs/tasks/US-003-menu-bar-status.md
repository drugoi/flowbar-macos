# US-003 Menu Bar Status Icon States

As a listener, I want the menu bar icon to reflect the app state so I can tell at a glance whether it is downloading, playing, paused, or idle.

## Acceptance Criteria
- Icon changes for idle, resolving, downloading, playing, paused, and error states.
- State derives from playback and download status, not hardcoded timers.
- Icon updates within 1 second of a state change.
- Accessibility label reflects the current state.
