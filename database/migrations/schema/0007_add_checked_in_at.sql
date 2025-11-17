-- Adds timestamp tracking for when attendees check in to events.
alter table event_attendee add column checked_in_at timestamptz;
