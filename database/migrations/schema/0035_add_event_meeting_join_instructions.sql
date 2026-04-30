-- Add manual meeting join instructions for event and session meetings.

alter table event
    add column meeting_join_instructions text check (btrim(meeting_join_instructions) <> '');

alter table session
    add column meeting_join_instructions text check (btrim(meeting_join_instructions) <> '');

alter table event
    drop constraint if exists event_meeting_conflict_chk;

alter table event
    add constraint event_meeting_conflict_chk check (
        not (
            meeting_requested = true
            and (
                meeting_join_instructions is not null
                or meeting_join_url is not null
            )
        )
    );

alter table session
    drop constraint if exists session_meeting_conflict_chk;

alter table session
    add constraint session_meeting_conflict_chk check (
        not (
            meeting_requested = true
            and (
                meeting_join_instructions is not null
                or meeting_join_url is not null
            )
        )
    );
