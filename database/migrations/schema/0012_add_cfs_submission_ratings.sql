-- Add ratings support for CFS submissions.

-- =============================================================================
-- CFS SUBMISSION RATING TABLE
-- =============================================================================

create table cfs_submission_rating (
    cfs_submission_id uuid not null references cfs_submission on delete cascade,
    reviewer_id uuid not null references "user",
    stars smallint not null check (stars between 1 and 5),

    comments text check (btrim(comments) <> ''),
    created_at timestamptz not null default current_timestamp,
    updated_at timestamptz,

    primary key (cfs_submission_id, reviewer_id)
);

create index cfs_submission_rating_reviewer_id_idx
on cfs_submission_rating (reviewer_id);
