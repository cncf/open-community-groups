-- Add post-event surveys, their responses and the survey notification.

-- Surveys organizers attach to an event.
create table event_survey (
    event_survey_id uuid primary key default gen_random_uuid(),
    anonymous boolean not null default true,
    audience text not null default 'confirmed',
    created_at timestamptz not null default current_timestamp,
    event_id uuid not null references event on delete cascade,
    questions jsonb not null default '[]'::jsonb,
    revision bigint not null default 1,
    status text not null default 'draft',
    title text not null,

    closed_at timestamptz,
    closes_at timestamptz,
    created_by uuid references "user" on delete set null,
    description text,
    first_response_at timestamptz,
    open_notification_processed_at timestamptz,
    open_notification_recipients int,
    opens_at timestamptz,
    updated_at timestamptz,

    constraint event_survey_audience_chk check (audience in ('checked-in', 'confirmed')),
    constraint event_survey_dates_chk check (
        closes_at is null or opens_at is null or closes_at > opens_at
    ),
    constraint event_survey_description_chk check (
        description is null or btrim(description) <> ''
    ),
    constraint event_survey_draft_chk check (
        status = 'ready'
        or (
            closed_at is null
            and first_response_at is null
            and open_notification_processed_at is null
        )
    ),
    constraint event_survey_open_notification_chk check (
        (open_notification_processed_at is null) = (open_notification_recipients is null)
        and (open_notification_recipients is null or open_notification_recipients >= 0)
    ),
    constraint event_survey_questions_chk check (jsonb_typeof(questions) = 'array'),
    constraint event_survey_revision_chk check (revision > 0),
    constraint event_survey_status_chk check (status in ('draft', 'ready')),
    constraint event_survey_title_chk check (btrim(title) <> '')
);

-- Support survey lookups by event, creator deletes and the opening notification job.
create index event_survey_created_by_idx on event_survey (created_by);
create index event_survey_event_id_idx on event_survey (event_id);
create index event_survey_open_notification_due_idx
    on event_survey (event_id)
    where status = 'ready'
    and open_notification_processed_at is null
    and closed_at is null;

-- One editable response per survey and user.
create table event_survey_response (
    answers jsonb not null,
    created_at timestamptz not null default current_timestamp,
    event_survey_id uuid not null
        references event_survey on delete cascade,
    user_id uuid not null references "user" on delete cascade,

    updated_at timestamptz,

    primary key (event_survey_id, user_id),
    constraint event_survey_response_answers_chk check (jsonb_typeof(answers) = 'object')
);

-- Support response pagination per survey and cascades from deleted users.
create index event_survey_response_survey_created_idx
    on event_survey_response (event_survey_id, created_at, user_id);
create index event_survey_response_user_id_idx
    on event_survey_response (user_id);

-- Register the event surveys category, which users can turn off and groups can mute.
insert into notification_category (
    notification_category_id, display_name, group_mutable
) values ('event-surveys', 'Event surveys', true);

-- Register the survey opening notification kind in the new category.
insert into notification_kind (name, notification_category_id)
values ('event-survey-opened', 'event-surveys');

-- Start from the Event reminders choice; categories are independent later.
insert into user_notification_opt_out (notification_category_id, user_id)
select 'event-surveys', o.user_id
from user_notification_opt_out o
where o.notification_category_id = 'event-reminders';
