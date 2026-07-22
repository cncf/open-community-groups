-- Apply safely to both the pre-baseline production schema and fresh baseline databases.
alter table event
    add column if not exists registration_questions jsonb not null default '[]'::jsonb;

alter table event_attendee
    add column if not exists registration_answers jsonb,
    drop constraint if exists event_attendee_status_check,
    drop constraint if exists event_attendee_status_chk,
    add constraint event_attendee_status_chk check (
        status in (
            'confirmed',
            'invitation-canceled',
            'invitation-pending',
            'invitation-rejected',
            'registration-questions-pending'
        )
    );

alter table event_invitation_request
    add column if not exists registration_answers jsonb;

create index if not exists event_attendee_event_id_registration_answers_idx
    on event_attendee (event_id)
    where registration_answers is not null;

create index if not exists event_invitation_request_event_id_registration_answers_idx
    on event_invitation_request (event_id)
    where registration_answers is not null;
