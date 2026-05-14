-- Store all raw provider recording URLs for a meeting.

-- Add the new array column with an empty-array default
alter table meeting
    add column recording_urls text[] default array[]::text[] not null;

-- Backfill the new recording URL array from the legacy single URL
update meeting
set recording_urls = array[recording_url]
where recording_url is not null;

-- Enforce clean array values before removing the legacy column
alter table meeting
    add constraint meeting_recording_urls_not_empty_chk check (
        array_position(recording_urls, null) is null
        and array_position(recording_urls, '') is null
    );

-- Drop the legacy single raw recording URL
alter table meeting
    drop column recording_url;

-- Raw provider URLs are no longer public fallbacks for events
update event
set meeting_recording_published = false
where meeting_recording_published = true
and meeting_recording_url is null;

-- Raw provider URLs are no longer public fallbacks for sessions
do $$
begin
    -- Avoid failing this data cleanup on pre-existing legacy session bounds
    perform set_config('ocg.skip_session_bounds_check', 'on', true);

    update session
    set meeting_recording_published = false
    where meeting_recording_published = true
    and meeting_recording_url is null;
end;
$$;
