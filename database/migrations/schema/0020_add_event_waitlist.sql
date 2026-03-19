-- Add waitlist support for event attendance.

-- Extend events with waitlist configuration
alter table event
    add column waitlist_enabled boolean not null default false,
    add constraint event_waitlist_capacity_required_chk check (
        not (waitlist_enabled = true and capacity is null)
    );

-- Store queued attendees per event in FIFO order
create table event_waitlist (
    event_id uuid not null references event,
    user_id uuid not null references "user",
    created_at timestamptz default current_timestamp not null,

    primary key (event_id, user_id)
);

create index event_waitlist_user_id_idx on event_waitlist (user_id);
create index event_waitlist_event_id_created_at_idx on event_waitlist (event_id, created_at);

-- Prevent attendee writes from creating a cross-table attendee/waitlist duplicate
create or replace function check_event_attendee_waitlist()
returns trigger as $$
begin
    -- Serialize writes for the same event-user pair across both attendance tables
    perform pg_advisory_xact_lock(hashtext(NEW.event_id::text), hashtext(NEW.user_id::text));

    if exists (
        select 1
        from event_waitlist
        where event_id = NEW.event_id
        and user_id = NEW.user_id
    ) then
        raise exception 'user is already on the waiting list for this event';
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Prevent waitlist writes from creating a cross-table attendee/waitlist duplicate
create or replace function check_event_waitlist_attendee()
returns trigger as $$
begin
    -- Serialize writes for the same event-user pair across both attendance tables
    perform pg_advisory_xact_lock(hashtext(NEW.event_id::text), hashtext(NEW.user_id::text));

    if exists (
        select 1
        from event_attendee
        where event_id = NEW.event_id
        and user_id = NEW.user_id
    ) then
        raise exception 'user is already attending this event';
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Enforce cross-table attendee and waitlist exclusivity on attendee writes
create trigger event_attendee_waitlist_check
    before insert or update of event_id, user_id on event_attendee
    for each row
    execute function check_event_attendee_waitlist();

-- Enforce cross-table attendee and waitlist exclusivity on waitlist writes
create trigger event_waitlist_attendee_check
    before insert or update of event_id, user_id on event_waitlist
    for each row
    execute function check_event_waitlist_attendee();

-- Register notification kinds used by waitlist lifecycle emails
insert into notification_kind (name) values ('event-waitlist-joined');
insert into notification_kind (name) values ('event-waitlist-left');
insert into notification_kind (name) values ('event-waitlist-promoted');

-- Recreate functions whose signatures or names changed in this migration
drop function if exists attend_event(uuid, uuid, uuid);
drop function if exists is_event_attendee(uuid, uuid, uuid);
drop function if exists leave_event(uuid, uuid, uuid);
drop function if exists update_event(uuid, uuid, jsonb, jsonb);
