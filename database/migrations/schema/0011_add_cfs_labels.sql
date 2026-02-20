-- Add CFS labels support for events and submissions.

-- =============================================================================
-- CFS LABEL TABLES
-- =============================================================================

create table event_cfs_label (
    color text not null,
    created_at timestamptz not null default current_timestamp,
    event_id uuid not null references event on delete cascade,
    event_cfs_label_id uuid primary key default gen_random_uuid(),
    name text not null check (btrim(name) <> '' and char_length(name) <= 80),

    unique (event_id, name)
);

create index event_cfs_label_event_id_idx on event_cfs_label (event_id);

create table cfs_submission_label (
    cfs_submission_id uuid not null references cfs_submission on delete cascade,
    created_at timestamptz not null default current_timestamp,
    event_cfs_label_id uuid not null references event_cfs_label on delete cascade,

    primary key (cfs_submission_id, event_cfs_label_id)
);

create index cfs_submission_label_event_cfs_label_id_idx
on cfs_submission_label (event_cfs_label_id);

-- =============================================================================
-- DROPS REQUIRED FOR FUNCTION SIGNATURE CHANGES
-- =============================================================================

drop function if exists add_cfs_submission(uuid, uuid, uuid, uuid);
drop function if exists update_cfs_submission(uuid, uuid, uuid, jsonb);
