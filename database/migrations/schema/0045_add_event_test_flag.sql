-- Add a flag for events created only for testing.

alter table event
    add column test_event boolean default false not null;
