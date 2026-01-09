# US-008 Smart Cache Management

As a listener with limited storage, I want the app to manage cache size automatically so I do not run out of disk space.

## Acceptance Criteria
- User can set a maximum cache size.
- When the limit is exceeded, the oldest unplayed or least-recently-played downloads are removed.
- Cache cleanup never removes the currently playing track.
- A summary shows current cache size and limit.
