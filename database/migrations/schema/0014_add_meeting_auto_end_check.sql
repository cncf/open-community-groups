-- Add auto-end check tracking to avoid reprocessing overdue meetings.
alter table meeting
    add column auto_end_check_at timestamptz,
    add column auto_end_check_outcome text;

-- Lookup values for meeting auto-end check outcomes.
create table meeting_auto_end_check_outcome (
    meeting_auto_end_check_outcome_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

insert into meeting_auto_end_check_outcome (meeting_auto_end_check_outcome_id, display_name)
values
    ('already_not_running', 'Already not running'),
    ('auto_ended', 'Auto ended'),
    ('error', 'Error'),
    ('not_found', 'Not found');

-- Ensure meeting auto-end check outcomes reference known lookup values.
alter table meeting
    add constraint meeting_auto_end_check_outcome_fk
        foreign key (auto_end_check_outcome)
            references meeting_auto_end_check_outcome (meeting_auto_end_check_outcome_id);

-- Require check timestamp and outcome to be set together.
alter table meeting
    add constraint meeting_auto_end_check_pair_chk
        check (
            (auto_end_check_at is null and auto_end_check_outcome is null)
            or (auto_end_check_at is not null and auto_end_check_outcome is not null)
        );

-- Index pending Zoom meetings that still need auto-end checks.
create index meeting_zoom_auto_end_pending_idx
    on meeting (meeting_provider_id, auto_end_check_at)
    where meeting_provider_id = 'zoom'
      and auto_end_check_at is null;
