-- Allow organizer-managed recording overrides on automatic event and session meetings.

alter table event
    drop constraint if exists event_meeting_conflict_chk;

alter table event
    add constraint event_meeting_conflict_chk check (
        not (meeting_requested = true and meeting_join_url is not null)
    );

alter table session
    drop constraint if exists session_meeting_conflict_chk;

alter table session
    add constraint session_meeting_conflict_chk check (
        not (meeting_requested = true and meeting_join_url is not null)
    );
