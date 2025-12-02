-- Meeting providers.
create table meeting_provider (
    meeting_provider_id text primary key,
    display_name text not null unique
);

insert into meeting_provider values ('zoom', 'Zoom');

-- Meetings table (external provider meetings integration).
create table meeting (
    meeting_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    join_url text not null check (join_url <> ''),
    meeting_provider_id text not null references meeting_provider,
    provider_meeting_id text not null check (provider_meeting_id <> ''),

    event_id uuid references event(event_id) on delete set null,
    password text,
    recording_url text check (recording_url <> ''),
    session_id uuid references session(session_id) on delete set null,
    updated_at timestamptz
);

create unique index meeting_event_id_idx on meeting (event_id);
create index meeting_meeting_provider_id_idx on meeting (meeting_provider_id);
create unique index meeting_meeting_provider_id_provider_meeting_id_idx on meeting (meeting_provider_id, provider_meeting_id);
create unique index meeting_session_id_idx on meeting (session_id);

-- Event meeting integration.
alter table event
    rename column recording_url to meeting_recording_url;
alter table event
    rename column streaming_url to meeting_join_url;
alter table event
    add column meeting_error text check (meeting_error <> ''),
    add column meeting_in_sync boolean,
    add column meeting_provider_id text references meeting_provider,
    add column meeting_requested boolean,
    add column meeting_requires_password boolean,
    add constraint event_meeting_conflict_chk check (
        not (
            meeting_requested = true
            and (meeting_join_url is not null or meeting_recording_url is not null)
        )
    ),
    add constraint event_meeting_kind_chk check (
        not (
            meeting_requested = true
            and event_kind_id not in ('hybrid', 'virtual')
        )
    ),
    add constraint event_meeting_provider_required_chk check (
        not (meeting_requested = true and meeting_provider_id is null)
    ),
    add constraint event_meeting_requested_times_chk check (
        not (meeting_requested = true and (starts_at is null or ends_at is null))
    );

create index event_meeting_sync_idx on event (meeting_requested, meeting_in_sync)
where meeting_requested = true and meeting_in_sync = false;

-- Session meeting integration.
alter table session
    rename column recording_url to meeting_recording_url;
alter table session
    rename column streaming_url to meeting_join_url;
alter table session
    add column meeting_error text check (meeting_error <> ''),
    add column meeting_in_sync boolean,
    add column meeting_provider_id text references meeting_provider,
    add column meeting_requested boolean,
    add column meeting_requires_password boolean,
    add constraint session_meeting_conflict_chk check (
        not (
            meeting_requested = true
            and (meeting_join_url is not null or meeting_recording_url is not null)
        )
    ),
    add constraint session_meeting_provider_required_chk check (
        not (meeting_requested = true and meeting_provider_id is null)
    ),
    add constraint session_meeting_requested_times_chk check (
        not (meeting_requested = true and (starts_at is null or ends_at is null))
    );

create index session_meeting_sync_idx on session (meeting_requested, meeting_in_sync)
where meeting_requested = true and meeting_in_sync = false;

-- Allow hard-deleting events with sessions (cascades to sessions).
alter table session drop constraint session_event_id_fkey;
alter table session add constraint session_event_id_fkey
    foreign key (event_id) references event(event_id) on delete cascade;

-- Allow hard-deleting sessions with speakers (cascades to session_speaker).
alter table session_speaker drop constraint session_speaker_session_id_fkey;
alter table session_speaker add constraint session_speaker_session_id_fkey
    foreign key (session_id) references session(session_id) on delete cascade;
