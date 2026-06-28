-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '7a210000-0000-0000-0000-000000000001'
\set eventCategoryID '7a210000-0000-0000-0000-000000000002'
\set eventID '7a210000-0000-0000-0000-000000000003'
\set groupCategoryID '7a210000-0000-0000-0000-000000000004'
\set groupID '7a210000-0000-0000-0000-000000000005'
\set meetingID '7a210000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'test-alliance',
    'Test Alliance',
    'A test alliance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Conference');

insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'A test group'
);

insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    starts_at,
    ends_at,
    timezone,
    capacity,
    meeting_in_sync,
    meeting_provider_id,
    meeting_recording_requested,
    meeting_requested,
    published
) values (
    :'eventID',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Google Meet Recording Event',
    'google-meet-recording-event',
    'Test event for Google Meet recording publish',
    current_timestamp - interval '2 hours',
    current_timestamp - interval '1 hour',
    'America/New_York',
    25,
    true,
    'google_meet',
    true,
    true,
    true
);

insert into meeting (
    meeting_id,
    event_id,
    meeting_provider_id,
    provider_meeting_id,
    join_url
) values (
    :'meetingID',
    :'eventID',
    'google_meet',
    'calendar-event-id',
    'https://meet.google.com/abc-defg-hij'
);

-- ============================================================================
-- TESTS
-- ============================================================================

select isnt(
    claim_google_meet_recording_for_publish(0, 60),
    null,
    'completed Google Meet event meeting is claimed for recording publish'
);

select isnt(
    (select recording_publish_claimed_at from meeting where meeting_id = :'meetingID'),
    null,
    'claim timestamp is recorded'
);

select is(
    claim_google_meet_recording_for_publish(0, 60),
    null,
    'claimed meeting is not claimed twice'
);

select lives_ok(
    format(
        $$select release_google_meet_recording_publish_claim(%L::uuid, %L::timestamptz, 'not found yet')$$,
        :'meetingID',
        (select recording_publish_claimed_at from meeting where meeting_id = :'meetingID')
    ),
    'claim can be released for retry'
);

select is(
    (select recording_publish_error from meeting where meeting_id = :'meetingID'),
    'not found yet',
    'release records latest error'
);

select isnt(
    claim_google_meet_recording_for_publish(0, 0),
    null,
    'released meeting can be claimed again after retry delay'
);

select lives_ok(
    format(
        $$select mark_google_meet_recording_published(%L::uuid, %L::timestamptz, 'drive-file-id', 'https://youtu.be/video-id')$$,
        :'meetingID',
        (select recording_publish_claimed_at from meeting where meeting_id = :'meetingID')
    ),
    'published recording can be marked complete'
);

select results_eq(
    format(
        $$select recording_publish_drive_file_id, recording_publish_url, recording_urls, meeting_recording_url, meeting_recording_published
          from meeting m
          join event e on e.event_id = m.event_id
          where m.meeting_id = %L::uuid$$,
        :'meetingID'
    ),
    $$ values ('drive-file-id'::text, 'https://youtu.be/video-id'::text, array['https://youtu.be/video-id']::text[], 'https://youtu.be/video-id'::text, true) $$,
    'YouTube URL is stored on meeting and event'
);

select * from finish();
rollback;
