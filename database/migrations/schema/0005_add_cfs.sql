-- Add call for speakers support.

-- =============================================================================
-- EVENT CFS FIELDS
-- =============================================================================

alter table event
    add column cfs_description text check (btrim(cfs_description) <> ''),
    add column cfs_enabled boolean,
    add column cfs_ends_at timestamptz,
    add column cfs_starts_at timestamptz;

alter table event
    add constraint event_cfs_fields_chk check (
        (
            cfs_enabled is true
            and cfs_description is not null
            and cfs_starts_at is not null
            and cfs_ends_at is not null
        )
        or (
            cfs_enabled is not true
            and cfs_description is null
            and cfs_starts_at is null
            and cfs_ends_at is null
        )
    ),
    add constraint event_cfs_window_chk check (
        cfs_enabled is not true
        or (
            cfs_starts_at < cfs_ends_at
            and starts_at is not null
            and cfs_starts_at < starts_at
            and cfs_ends_at < starts_at
        )
    );

-- =============================================================================
-- CFS LOOKUP TABLES
-- =============================================================================

create table cfs_submission_status (
    cfs_submission_status_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

insert into cfs_submission_status values ('approved', 'Approved');
insert into cfs_submission_status values ('information-requested', 'Information requested');
insert into cfs_submission_status values ('not-reviewed', 'Not reviewed');
insert into cfs_submission_status values ('rejected', 'Rejected');
insert into cfs_submission_status values ('withdrawn', 'Withdrawn');

create table session_proposal_level (
    session_proposal_level_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

insert into session_proposal_level values ('advanced', 'Advanced');
insert into session_proposal_level values ('beginner', 'Beginner');
insert into session_proposal_level values ('intermediate', 'Intermediate');

-- =============================================================================
-- SESSION PROPOSALS AND SUBMISSIONS
-- =============================================================================

create table session_proposal (
    created_at timestamptz not null default current_timestamp,
    description text not null check (btrim(description) <> ''),
    duration interval not null,
    session_proposal_id uuid primary key default gen_random_uuid(),
    session_proposal_level_id text not null references session_proposal_level,
    title text not null check (btrim(title) <> ''),
    user_id uuid not null references "user",

    co_speaker_user_id uuid references "user",
    updated_at timestamptz,

    check (co_speaker_user_id is null or co_speaker_user_id <> user_id)
);

create index session_proposal_co_speaker_user_id_idx on session_proposal (co_speaker_user_id);
create index session_proposal_session_proposal_level_id_idx on session_proposal (session_proposal_level_id);
create index session_proposal_user_id_idx on session_proposal (user_id);

create table cfs_submission (
    cfs_submission_id uuid primary key default gen_random_uuid(),
    created_at timestamptz not null default current_timestamp,
    event_id uuid not null references event,
    session_proposal_id uuid not null references session_proposal,
    status_id text not null references cfs_submission_status,

    action_required_message text check (btrim(action_required_message) <> ''),
    reviewed_by uuid references "user",
    updated_at timestamptz,

    unique (event_id, session_proposal_id)
);

create index cfs_submission_event_id_idx on cfs_submission (event_id);
create index cfs_submission_reviewed_by_idx on cfs_submission (reviewed_by);
create index cfs_submission_session_proposal_id_idx on cfs_submission (session_proposal_id);
create index cfs_submission_status_id_idx on cfs_submission (status_id);

-- =============================================================================
-- SESSION LINKING TO SUBMISSIONS
-- =============================================================================

alter table session
    add column cfs_submission_id uuid references cfs_submission;

create unique index session_cfs_submission_id_unique_idx
    on session (cfs_submission_id)
    where cfs_submission_id is not null;

-- Trigger function to ensure linked submissions are approved and match the event.
create or replace function check_session_cfs_submission_approved()
returns trigger as $$
declare
    v_event_id uuid;
    v_status_id text;
begin
    -- Skip validation when no submission is linked
    if NEW.cfs_submission_id is null then
        return NEW;
    end if;

    -- Fetch submission event and status
    select cs.event_id, cs.status_id
    into v_event_id, v_status_id
    from cfs_submission cs
    where cs.cfs_submission_id = NEW.cfs_submission_id;

    -- Ensure submission exists
    if v_event_id is null then
        raise exception 'cfs submission not found';
    end if;

    -- Ensure submission belongs to the same event
    if v_event_id <> NEW.event_id then
        raise exception 'cfs submission does not belong to the session event';
    end if;

    -- Ensure submission is approved
    if v_status_id <> 'approved' then
        raise exception 'cfs submission must be approved';
    end if;

    -- Return validated row
    return NEW;
end;
$$ language plpgsql;

create trigger session_cfs_submission_approved_check
    before insert or update on session
    for each row
    execute function check_session_cfs_submission_approved();

-- =============================================================================
-- NOTIFICATION KIND
-- =============================================================================

insert into notification_kind (name) values ('cfs-submission-updated');
