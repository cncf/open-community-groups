-- Adds the event-custom and group-custom notification kinds.
insert into notification_kind (name) values ('event-custom');
insert into notification_kind (name) values ('group-custom');

-- Custom notification tracking
-- This table tracks custom notifications sent by group owners
create table custom_notification (
    custom_notification_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    created_by uuid references "user" (user_id) on delete set null,
    event_id uuid references event (event_id) on delete cascade,
    group_id uuid references "group" (group_id) on delete cascade,
    subject text not null check (subject <> ''),
    body text not null check (body <> ''),

    -- Ensure either event_id or group_id is set, but not both
    check (
        (event_id is not null and group_id is null) or
        (event_id is null and group_id is not null)
    )
);

create index custom_notification_created_by_idx on custom_notification (created_by);
create index custom_notification_event_id_idx on custom_notification (event_id);
create index custom_notification_group_id_idx on custom_notification (group_id);
