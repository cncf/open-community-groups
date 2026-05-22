-- Add organizer-created event invitation state.

-- Track whether a user row is fully registered or only an invitation placeholder.
alter table "user"
    add column registration_status text not null default 'registered'
        check (registration_status in ('pre-registered', 'registered'));

-- Track attendee invitation lifecycle alongside confirmed attendance.
alter table event_attendee
    add column manually_invited boolean not null default false,
    add column status text not null default 'confirmed'
        check (
            status in (
                'confirmed',
                'invitation-canceled',
                'invitation-pending',
                'invitation-rejected'
            )
        );

-- Support attendee searches that filter by event and invitation status.
create index event_attendee_event_id_status_created_at_idx
    on event_attendee (event_id, status, created_at);

-- Allow organizer-created event invitation notifications.
insert into notification_kind (name) values ('event-invitation');
