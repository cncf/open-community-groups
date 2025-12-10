-- Add constraint to ensure checked_in and checked_in_at are consistent.
alter table event_attendee
add constraint event_attendee_checked_in_consistency_chk check (
    (checked_in = false and checked_in_at is null) or
    (checked_in = true and checked_in_at is not null)
);
