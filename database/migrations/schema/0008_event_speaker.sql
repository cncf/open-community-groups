-- Adds an event-level speakers table.
create table event_speaker (
    created_at timestamptz default current_timestamp not null,
    featured boolean default false not null,
    event_id uuid not null references event,
    user_id uuid not null references "user",

    primary key (event_id, user_id)
);

create index event_speaker_event_id_idx on event_speaker (event_id);
create index event_speaker_user_id_idx on event_speaker (user_id);
