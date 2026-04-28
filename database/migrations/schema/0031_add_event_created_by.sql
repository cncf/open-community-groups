-- Track the user who created an event for dashboard metadata.

alter table event
    add column created_by uuid references "user" on delete set null;
