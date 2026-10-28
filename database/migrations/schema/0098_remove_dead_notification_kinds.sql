-- Removes the notification kinds that no code path enqueues or renders.

-- Bound lock waits so the migration fails instead of stalling the app.
set local lock_timeout = '5s';

-- Delete queued and delivered notifications of the removed kinds; their
-- attachment links cascade and notification.kind restricts kind deletion.
delete from notification
where kind in ('event-invitation', 'event-waitlist-promoted');

-- Delete the removed notification kinds.
delete from notification_kind
where name in ('event-invitation', 'event-waitlist-promoted');
