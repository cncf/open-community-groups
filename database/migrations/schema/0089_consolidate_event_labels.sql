-- Share event labels between sessions and CFS submissions.

-- =============================================================================
-- EVENT LABELS
-- =============================================================================

-- Rename the event label table and its identifier.
alter table event_cfs_label rename to event_label;
alter table event_label rename column event_cfs_label_id to event_label_id;

-- Rename the event label constraints and indexes.
alter table event_label rename constraint event_cfs_label_event_id_fkey to event_label_event_id_fkey;
alter table event_label rename constraint event_cfs_label_name_check to event_label_name_check;
alter table event_label rename constraint event_cfs_label_pkey to event_label_pkey;
alter index event_cfs_label_event_id_idx rename to event_label_event_id_idx;

-- Allow label names to be swapped within one transaction.
alter table event_label drop constraint event_cfs_label_event_id_name_key;
alter table event_label
add constraint event_label_event_id_name_key
unique (event_id, name) deferrable initially immediate;

-- =============================================================================
-- CFS SUBMISSION LABELS
-- =============================================================================

-- Rename the CFS submission label reference.
alter table cfs_submission_label rename column event_cfs_label_id to event_label_id;
alter table cfs_submission_label
rename constraint cfs_submission_label_event_cfs_label_id_fkey
to cfs_submission_label_event_label_id_fkey;
alter index cfs_submission_label_event_cfs_label_id_idx
rename to cfs_submission_label_event_label_id_idx;

-- =============================================================================
-- SESSION LABELS
-- =============================================================================

-- Link sessions to the labels of their event.
create table session_label (
    created_at timestamptz not null default current_timestamp,
    event_label_id uuid not null references event_label on delete cascade,
    session_id uuid not null references session on delete cascade,

    primary key (session_id, event_label_id)
);

create index session_label_event_label_id_idx on session_label (event_label_id);

-- =============================================================================
-- BACKFILL
-- =============================================================================

-- Reject linked submission labels that belong to another event.
do $$
begin
    -- Fail loudly on inconsistent session and submission history
    if exists (
        select 1
        from session s
        join cfs_submission_label csl on csl.cfs_submission_id = s.cfs_submission_id
        join event_label el on el.event_label_id = csl.event_label_id
        where el.event_id <> s.event_id
    ) then
        raise exception 'linked submission labels belong to another event';
    end if;
end;
$$;

-- Copy the labels of linked submissions onto their sessions.
insert into session_label (event_label_id, session_id)
select csl.event_label_id, s.session_id
from session s
join cfs_submission_label csl on csl.cfs_submission_id = s.cfs_submission_id
join event_label el on el.event_label_id = csl.event_label_id
                   and el.event_id = s.event_id;

-- =============================================================================
-- DROPS REQUIRED FOR FUNCTION RENAMES
-- =============================================================================

drop function if exists list_event_cfs_labels(uuid);
drop function if exists sync_event_cfs_labels(uuid, jsonb);
drop function if exists validate_cfs_submission_label_ids(uuid, uuid[]);
drop function if exists validate_event_cfs_labels_payload(jsonb);
