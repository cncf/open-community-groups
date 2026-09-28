-- Add event co-hosting between groups.

-- Catalog of lifecycle states for an event co-host invitation.
create table event_cohost_status (
    event_cohost_status_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

-- Seed the supported co-host lifecycle states.
insert into event_cohost_status (event_cohost_status_id, display_name) values
    ('approved', 'Approved'),
    ('canceled', 'Canceled'),
    ('event-canceled', 'Event canceled'),
    ('event-deleted', 'Event deleted'),
    ('pending', 'Pending'),
    ('rejected', 'Rejected'),
    ('removed', 'Removed');

-- Track groups invited to co-host an event and their invitation lifecycle.
create table event_cohost (
    event_id uuid not null references event,
    event_cohost_status_id text not null default 'pending' references event_cohost_status,
    group_id uuid not null references "group",
    invitation_id uuid not null default gen_random_uuid() unique,
    invited_at timestamptz default current_timestamp not null,
    updated_at timestamptz default current_timestamp not null,

    approved_at timestamptz,
    invited_by uuid references "user",
    responded_at timestamptz,
    responded_by uuid references "user",

    constraint event_cohost_approved_at_chk check (
        event_cohost_status_id <> 'approved'
        or approved_at is not null
    ),
    constraint event_cohost_pending_approval_chk check (
        event_cohost_status_id <> 'pending'
        or approved_at is null
    ),
    primary key (event_id, group_id)
);

-- Support co-host lookups by event and by group, filtered by status.
create index event_cohost_event_id_status_idx on event_cohost (
    event_id,
    event_cohost_status_id
);
create index event_cohost_group_id_status_idx on event_cohost (
    group_id,
    event_cohost_status_id
);

-- Version the event co-host set so concurrent edits can be detected.
alter table event
add column cohosts_revision int not null default 0;

-- Rejects co-host rows that point back at the owning event group.
create or replace function check_event_cohost_group()
returns trigger as $$
declare
    v_event_group_id uuid;
begin
    -- Resolve the group that owns the event
    select group_id
    into v_event_group_id
    from event
    where event_id = new.event_id;

    -- Reject self co-hosting
    if new.group_id = v_event_group_id then
        raise exception 'event group cannot co-host its own event';
    end if;

    -- Return the validated co-host row
    return new;
end;
$$ language plpgsql;

-- Validate co-host groups whenever the event or group reference changes.
create trigger event_cohost_group_check
before insert or update of event_id, group_id on event_cohost
for each row execute function check_event_cohost_group();

-- Register the notifications sent during the co-host invitation lifecycle.
insert into notification_kind (name, optional_notification) values
    ('event-cohost-invitation', false),
    ('event-cohost-removed', false),
    ('event-cohost-responded', false);
