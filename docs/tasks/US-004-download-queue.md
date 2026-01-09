# US-004 Download Queue

As a listener adding multiple tracks, I want downloads to queue automatically so I can add several items and let them download in order.

## Acceptance Criteria
- Multiple downloads can be queued from the UI.
- Only one download runs at a time; the next starts automatically.
- Queue order is deterministic (first requested, first downloaded).
- Users can cancel the active download; queued items remain.
- UI shows which item is downloading and which are queued.
