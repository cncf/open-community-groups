-- Add organizer control for public recording visibility.

alter table event
    add column meeting_recording_published boolean default false not null;

alter table session
    add column meeting_recording_published boolean default false not null;

update event e
set meeting_recording_published = true
where e.meeting_recording_url is not null
or exists (
    select 1
    from meeting m
    where m.event_id = e.event_id
    and m.recording_url is not null
);

update session s
set meeting_recording_published = true
where s.meeting_recording_url is not null
or exists (
    select 1
    from meeting m
    where m.session_id = s.session_id
    and m.recording_url is not null
);
