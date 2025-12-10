-- Add CHECK constraints to prevent ends_at being before starts_at and to
-- ensure starts_at is set when ends_at is set.

-- Event table
alter table event add constraint event_ends_at_after_starts_at_check
    check (ends_at is null or (starts_at is not null and ends_at >= starts_at));

-- Session table
alter table session add constraint session_ends_at_after_starts_at_check
    check (ends_at is null or (starts_at is not null and ends_at >= starts_at));
