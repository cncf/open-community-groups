-- Prepare notification delivery rate limiting.

-- Remove the old zero-argument function before adding defaulted parameters.
drop function if exists claim_pending_notification();

-- Support rolling-window counts over recent delivery reservations.
create index notification_delivery_claimed_at_idx
on notification (delivery_claimed_at)
where delivery_claimed_at is not null;
