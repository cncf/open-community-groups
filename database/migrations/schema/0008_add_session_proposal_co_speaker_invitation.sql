-- Add session proposal co-speaker invitation workflow.

-- =============================================================================
-- SESSION PROPOSAL STATUSES
-- =============================================================================

create table session_proposal_status (
    session_proposal_status_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

insert into session_proposal_status values
    ('declined-by-co-speaker', 'Declined by co-speaker'),
    ('pending-co-speaker-response', 'Awaiting co-speaker response'),
    ('ready-for-submission', 'Ready for submission');

alter table session_proposal
    add column session_proposal_status_id text references session_proposal_status;

update session_proposal
set session_proposal_status_id = 'ready-for-submission'
where session_proposal_status_id is null;

alter table session_proposal
    alter column session_proposal_status_id set default 'ready-for-submission',
    alter column session_proposal_status_id set not null;

create index session_proposal_status_id_idx on session_proposal (session_proposal_status_id);

-- =============================================================================
-- NOTIFICATION KIND
-- =============================================================================

insert into notification_kind (name) values ('session-proposal-co-speaker-invitation');
