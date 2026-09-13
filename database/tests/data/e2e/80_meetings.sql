-- E2E seed: meeting webhooks and rendering fixtures.
-- Depends on: 30_events.sql (meeting events), 40_users_badges.sql (users).

-- ============================================================================
-- MEETINGS
-- ============================================================================

-- Zoom recording webhook event meeting starts without raw provider recordings.
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,

    event_id,
    provider_host_user_id,
    recording_urls
) values (
    '88888888-8888-8888-8888-888888888943',
    'https://zoom.us/j/912345678901',
    'zoom',
    '912345678901',

    '55555555-5555-5555-5555-555555555943',
    'host@example.com',
    '{}'::text[]
);

-- Zoom live event meeting exposes a join URL during the attendee access window.
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,

    event_id,
    provider_host_user_id,
    recording_urls
) values (
    '88888888-8888-8888-8888-888888888944',
    'https://zoom.us/j/912345678902',
    'zoom',
    '912345678902',

    '55555555-5555-5555-5555-555555555944',
    'host@example.com',
    '{}'::text[]
);

-- Zoom public recording event meeting backs an already published final recording.
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,

    event_id,
    provider_host_user_id,
    recording_urls
) values (
    '88888888-8888-8888-8888-888888888947',
    'https://zoom.us/j/912345678903',
    'zoom',
    '912345678903',

    '55555555-5555-5555-5555-555555555947',
    'host@example.com',
    '{}'::text[]
);

-- Zoom unpublished recording event meeting backs an organizer-only final recording.
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,

    event_id,
    provider_host_user_id,
    recording_urls
) values (
    '88888888-8888-8888-8888-888888888948',
    'https://zoom.us/j/912345678904',
    'zoom',
    '912345678904',

    '55555555-5555-5555-5555-555555555948',
    'host@example.com',
    '{}'::text[]
);

-- ============================================================================
-- MEETING ATTENDEES
-- ============================================================================

-- Confirmed attendee used for live meeting join-link visibility.
insert into event_attendee (event_id, user_id)
values (
    '55555555-5555-5555-5555-555555555944',
    '77777777-7777-7777-7777-777777777705'
);
