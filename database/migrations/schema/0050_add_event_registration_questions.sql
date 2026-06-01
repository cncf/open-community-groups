-- Add registration questions and attendee answers.

-- Add event registration question storage.
alter table event
    add column registration_questions jsonb not null default '[]'::jsonb;

-- Add attendee registration answers and refresh status validation.
alter table event_attendee
    add column registration_answers jsonb,
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

-- Add invitation request registration answers.
alter table event_invitation_request
    add column registration_answers jsonb;

-- Index answered rows for questionnaire lock checks.
create index event_attendee_event_id_registration_answers_idx
    on event_attendee (event_id)
    where registration_answers is not null;
create index event_invitation_request_event_id_registration_answers_idx
    on event_invitation_request (event_id)
    where registration_answers is not null;
