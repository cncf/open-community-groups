-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(28);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set category1ID '3a3a0000-0000-0000-0000-000000000001'
\set category2ID '3a3a0000-0000-0000-0000-000000000002'
\set alliance1ID '3a3a0000-0000-0000-0000-000000000003'
\set event1ID '3a3a0000-0000-0000-0000-000000000004'
\set event8ID '3a3a0000-0000-0000-0000-000000000005'
\set event9ID '3a3a0000-0000-0000-0000-000000000006'
\set event14ID '3a3a0000-0000-0000-0000-000000000007'
\set eventShrinkBoundsID '3a3a0000-0000-0000-0000-000000000008'
\set group1ID '3a3a0000-0000-0000-0000-000000000009'
\set session3ID '3a3a0000-0000-0000-0000-000000000010'
\set sessionShrinkBoundsID '3a3a0000-0000-0000-0000-000000000011'
\set sponsorOrigID '3a3a0000-0000-0000-0000-000000000012'
\set user1ID '3a3a0000-0000-0000-0000-000000000013'
\set user3ID '3a3a0000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'alliance1ID',
    'test-alliance',
    'Test Alliance',
    'A test alliance for testing purposes',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Users
insert into "user" (user_id, auth_hash, email, username, name) values
    (:'user1ID', 'hash1', 'host1@example.com', 'host1', 'Host One'),
    (:'user3ID', 'hash3', 'speaker1@example.com', 'speaker1', 'Speaker One');

-- Event Category
insert into event_category (event_category_id, name, alliance_id)
values
    (:'category1ID', 'Conference', :'alliance1ID'),
    (:'category2ID', 'Workshop', :'alliance1ID');

-- Group Category
insert into group_category (group_category_id, name, alliance_id)
values ('3a3a0000-0000-0000-0000-000000000015', 'Technology', :'alliance1ID');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'group1ID',
    :'alliance1ID',
    'Test Group',
    'abc1234',
    'A test group',
    '3a3a0000-0000-0000-0000-000000000015'
);

-- Group Sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values (:'sponsorOrigID', :'group1ID', 'Original Sponsor', 'https://example.com/sponsor.png', null);

-- Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values (
    :'event1ID',
    :'group1ID',
    'Original Event',
    'def5678',
    'Original description',
    'America/New_York',
    :'category1ID',
    'in-person'
);

-- Published event used for attendee floor validation checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    published,
    starts_at
) values (
    :'event14ID',
    :'group1ID',
    'Capacity Validation Event',
    'capacity-validation',
    'Published event for attendee floor validation checks',
    'America/New_York',
    :'category1ID',
    'in-person',
    3,
    true,
    '2030-02-10 10:00:00-05'
);

-- Past Event (for testing past updates)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,

    description_short,
    photos_urls,
    tags,
    venue_name
) values (
    :'event8ID',
    :'group1ID',
    'Past Event',
    'stu5mno',
    'This event already happened',
    'America/New_York',
    :'category1ID',
    'in-person',
    '2020-01-01 10:00:00-05',
    '2020-01-01 12:00:00-05',

    'Original short description',
    array['https://example.com/original-photo.jpg'],
    array['original', 'tags'],
    'Original Venue'
);

-- Live Event (started in the past, ends in the future)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at
) values (
    :'event9ID',
    :'group1ID',
    'Live Event',
    'vwx6pqr',
    'This event is currently live',
    'UTC',
    :'category1ID',
    'in-person',
    current_timestamp - interval '1 hour',
    current_timestamp + interval '2 hours'
);

-- Session already completed while the live event is still ongoing
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_provider_id,
    meeting_requested
) values (
    :'session3ID',
    :'event9ID',
    'Completed Live Event Session',
    current_timestamp - interval '45 minutes',
    current_timestamp - interval '15 minutes',
    'virtual',
    'zoom',
    true
);

-- Event with session for bounds shrink checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at
) values (
    :'eventShrinkBoundsID',
    :'group1ID',
    'Shrink Bounds Event',
    'shrink-bounds-event',
    'This event has a session used for bounds shrink checks',
    'UTC',
    :'category1ID',
    'virtual',
    '2030-05-01 09:00:00+00',
    '2030-05-01 17:00:00+00'
);

-- Session near the end of the event for bounds shrink checks
insert into session (
    session_id,
    event_id,
    name,
    description,
    starts_at,
    ends_at,
    session_kind_id
) values (
    :'sessionShrinkBoundsID',
    :'eventShrinkBoundsID',
    'Shrink Bounds Session',
    'Session near the end of the event',
    '2030-05-01 15:00:00+00',
    '2030-05-01 16:00:00+00',
    'virtual'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should throw error when event ends_at is in the past
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Past End Event", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person", "ends_at": "2020-01-01T12:00:00"}'::jsonb
    )$$,
    'event ends_at cannot be in the past',
    'Should throw error when event ends_at is in the past'
);

-- Should throw error when session ends_at is in the past
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Session Past End", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "Past End Session", "starts_at": "2030-01-01T10:00:00", "ends_at": "2020-01-01T11:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session ends_at cannot be in the past',
    'Should throw error when session ends_at is in the past'
);

-- Should throw error when event ends_at is before starts_at
select throws_like(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Invalid Range Event", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person", "starts_at": "2030-01-01T12:00:00", "ends_at": "2030-01-01T10:00:00"}'::jsonb
    )$$,
    '%event_check%',
    'Should throw error when event ends_at is before starts_at'
);

-- Should throw error when session ends_at is before starts_at
select throws_like(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Invalid Session Range", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "Invalid Session", "starts_at": "2030-01-01T12:00:00", "ends_at": "2030-01-01T10:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    '%session_check%',
    'Should throw error when session ends_at is before starts_at'
);

-- Should throw error when event ends_at is set without starts_at
select throws_like(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "No Start Event", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person", "ends_at": "2030-01-01T12:00:00"}'::jsonb
    )$$,
    '%event_check%',
    'Should throw error when event ends_at is set without starts_at'
);

-- Should succeed with event ends_at null when starts_at is null
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "No Dates Event", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person"}'::jsonb
    )$$,
    'Should succeed with event ends_at null when starts_at is null'
);

-- Should reject clearing the start date on a published event
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000007'::uuid,
        '{"name": "Published No Dates Event", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person"}'::jsonb
    )$$,
    'published event must have a start date',
    'Should reject clearing the start date on a published event'
);

-- Should succeed with session ends_at null when starts_at is set
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Session No End", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "sessions": [{"name": "No End Session", "starts_at": "2030-01-01T10:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'Should succeed with session ends_at null when starts_at is set'
);

-- Should succeed with valid future dates for event and sessions
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Future Event", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Future Session", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T11:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'Should succeed with valid future dates for event and sessions'
);

-- Should throw error when session starts_at is before event starts_at
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Session Before Event", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Early Session", "starts_at": "2030-01-01T09:00:00", "ends_at": "2030-01-01T10:30:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session starts_at must be within event bounds',
    'Should throw error when session starts_at is before event starts_at'
);

-- Should throw error when session starts_at is after event ends_at
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Session After Event", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Late Session", "starts_at": "2030-01-01T13:00:00", "ends_at": "2030-01-01T14:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session starts_at must be within event bounds',
    'Should throw error when session starts_at is after event ends_at'
);

-- Should throw error when session ends_at is after event ends_at
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Session Exceeds Event", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T12:00:00", "sessions": [{"name": "Long Session", "starts_at": "2030-01-01T11:00:00", "ends_at": "2030-01-01T13:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'session ends_at must be within event bounds',
    'Should throw error when session ends_at is after event ends_at'
);

-- Should succeed when session is within event bounds
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Session Within Bounds", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00", "ends_at": "2030-01-01T14:00:00", "sessions": [{"name": "Valid Session", "starts_at": "2030-01-01T11:00:00", "ends_at": "2030-01-01T12:00:00", "kind": "in-person"}]}'::jsonb
    )$$,
    'Should succeed when session is within event bounds'
);

-- Should throw error when shrinking event bounds leaves a retained session out
-- of bounds (relies on the event row update running before the session sync)
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000008'::uuid,
        '{"name": "Shrink Bounds Event", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "virtual", "starts_at": "2030-05-01T09:00:00", "ends_at": "2030-05-01T12:00:00", "sessions": [{"session_id": "3a3a0000-0000-0000-0000-000000000011", "name": "Shrink Bounds Session", "starts_at": "2030-05-01T15:00:00", "ends_at": "2030-05-01T16:00:00", "kind": "virtual"}]}'::jsonb
    )$$,
    'session starts_at must be within event bounds',
    'Should throw error when shrinking event bounds leaves a retained session out of bounds'
);

-- Should succeed when shrinking event bounds keeps the retained session within bounds
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000008'::uuid,
        '{"name": "Shrink Bounds Event", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000001", "kind_id": "virtual", "starts_at": "2030-05-01T09:00:00", "ends_at": "2030-05-01T16:30:00", "sessions": [{"session_id": "3a3a0000-0000-0000-0000-000000000011", "name": "Shrink Bounds Session", "starts_at": "2030-05-01T15:00:00", "ends_at": "2030-05-01T16:00:00", "kind": "virtual"}]}'::jsonb
    )$$,
    'Should succeed when shrinking event bounds keeps the retained session within bounds'
);

-- Should update all fields on past events
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000005'::uuid,
        '{
            "name": "Past Event Updated",
            "description": "Updated description for past event",
            "timezone": "UTC",
            "category_id": "3a3a0000-0000-0000-0000-000000000002",
            "kind_id": "virtual",
            "capacity": 150,
            "starts_at": "2020-01-02T10:00:00",
            "ends_at": "2020-01-02T12:30:00",
            "banner_mobile_url": "https://example.com/banner-mobile.jpg",
            "banner_url": "https://example.com/banner.jpg",
            "description_short": "Updated short description",
            "logo_url": "https://example.com/logo.png",
            "luma_url": "https://luma.com/group/events/123456",
            "meetup_url": "https://meetup.com/group/events/123456",
            "meeting_join_url": "https://meet.example.com/room",
            "meeting_provider_id": "zoom",
            "meeting_recording_url": "https://youtube.com/recording",
            "meeting_requested": false,
            "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
            "registration_required": true,
            "tags": ["updated", "past", "event"],
            "venue_address": "123 Updated St",
            "venue_city": "Updated City",
            "venue_country_code": "US",
            "venue_country_name": "United States",
            "venue_name": "Updated Venue",
            "venue_state": "CA",
            "venue_zip_code": "12345",
            "hosts": ["3a3a0000-0000-0000-0000-000000000013"],
            "speakers": [{"user_id": "3a3a0000-0000-0000-0000-000000000014", "featured": true}],
            "sponsors": [{"group_sponsor_id": "3a3a0000-0000-0000-0000-000000000012", "level": "Gold"}],
            "sessions": [{"name": "Past Session", "starts_at": "2020-01-02T10:30:00", "ends_at": "2020-01-02T11:30:00", "kind": "virtual", "meeting_join_instructions": "Past session instructions"}]
        }'::jsonb
    )$$,
    'Should update all fields on past events'
);

-- Verify past event fields were updated
select is(
    (
        select jsonb_build_object(
            'banner_mobile_url', banner_mobile_url,
            'banner_url', banner_url,
            'capacity', capacity,
            'description', description,
            'description_short', description_short,
            'ends_at', ends_at,
            'event_category_id', event_category_id,
            'event_kind_id', event_kind_id,
            'logo_url', logo_url,
            'luma_url', luma_url,
            'meeting_join_url', meeting_join_url,
            'meeting_provider_id', meeting_provider_id,
            'meeting_recording_url', meeting_recording_url,
            'meeting_requested', meeting_requested,
            'meetup_url', meetup_url,
            'name', name,
            'photos_urls', photos_urls,
            'registration_required', registration_required,
            'starts_at', starts_at,
            'tags', tags,
            'timezone', timezone,
            'venue_address', venue_address,
            'venue_city', venue_city,
            'venue_country_code', venue_country_code,
            'venue_country_name', venue_country_name,
            'venue_name', venue_name,
            'venue_state', venue_state,
            'venue_zip_code', venue_zip_code
        )
        from event
        where event_id = :'event8ID'::uuid
    ),
    jsonb_build_object(
        'banner_mobile_url', 'https://example.com/banner-mobile.jpg',
        'banner_url', 'https://example.com/banner.jpg',
        'capacity', 150,
        'description', 'Updated description for past event',
        'description_short', 'Updated short description',
        'ends_at', '2020-01-02 12:30:00+00'::timestamptz,
        'event_category_id', :'category2ID'::uuid,
        'event_kind_id', 'virtual',
        'logo_url', 'https://example.com/logo.png',
        'luma_url', 'https://luma.com/group/events/123456',
        'meeting_join_url', 'https://meet.example.com/room',
        'meeting_provider_id', 'zoom',
        'meeting_recording_url', 'https://youtube.com/recording',
        'meeting_requested', false,
        'meetup_url', 'https://meetup.com/group/events/123456',
        'name', 'Past Event Updated',
        'photos_urls', array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
        'registration_required', true,
        'starts_at', '2020-01-02 10:00:00+00'::timestamptz,
        'tags', array['updated', 'past', 'event'],
        'timezone', 'UTC',
        'venue_address', '123 Updated St',
        'venue_city', 'Updated City',
        'venue_country_code', 'US',
        'venue_country_name', 'United States',
        'venue_name', 'Updated Venue',
        'venue_state', 'CA',
        'venue_zip_code', '12345'
    ),
    'Should update past event fields'
);

-- Should update hosts on past events
select is(
    (
        select array_agg(user_id order by user_id)
        from event_host
        where event_id = :'event8ID'::uuid
    ),
    array['3a3a0000-0000-0000-0000-000000000013']::uuid[],
    'Should update hosts on past events'
);

-- Should update speakers on past events
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'featured', featured,
                'user_id', user_id
            )
            order by user_id
        )
        from event_speaker
        where event_id = :'event8ID'::uuid
    ),
    '[{"featured": true, "user_id": "3a3a0000-0000-0000-0000-000000000014"}]'::jsonb,
    'Should update speakers on past events'
);

-- Should update sponsors on past events
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'group_sponsor_id', group_sponsor_id,
                'level', level
            )
            order by group_sponsor_id
        )
        from event_sponsor
        where event_id = :'event8ID'::uuid
    ),
    '[{"group_sponsor_id": "3a3a0000-0000-0000-0000-000000000012", "level": "Gold"}]'::jsonb,
    'Should update sponsors on past events'
);

-- Should update sessions on past events
select is(
    (
        select jsonb_build_object(
            'ends_at', ends_at,
            'meeting_join_instructions', meeting_join_instructions,
            'name', name,
            'session_kind_id', session_kind_id,
            'starts_at', starts_at
        )
        from session
        where event_id = :'event8ID'::uuid
        limit 1
    ),
    jsonb_build_object(
        'ends_at', '2020-01-02 11:30:00+00'::timestamptz,
        'meeting_join_instructions', 'Past session instructions',
        'name', 'Past Session',
        'session_kind_id', 'virtual',
        'starts_at', '2020-01-02 10:30:00+00'::timestamptz
    ),
    'Should update sessions on past events'
);

-- Should throw error when past event ends_at is in the future
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Future Past Event", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000002", "kind_id": "virtual", "starts_at": "2020-01-02T10:00:00", "ends_at": "2099-01-02T12:30:00"}'::jsonb
    )$$,
    'event ends_at cannot be in the future',
    'Should throw error when past event ends_at is in the future'
);

-- Should throw error when past event session starts_at is in the future
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Future Past Session", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000002", "kind_id": "virtual", "starts_at": "2020-01-02T10:00:00", "ends_at": "2020-01-02T12:30:00", "sessions": [{"name": "Future Session", "starts_at": "2099-01-02T10:30:00", "ends_at": "2020-01-02T11:30:00", "kind": "virtual"}]}'::jsonb
    )$$,
    'session starts_at cannot be in the future',
    'Should throw error when past event session starts_at is in the future'
);

-- Should throw error when past event session ends_at is in the future
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a3a0000-0000-0000-0000-000000000009'::uuid,
        '3a3a0000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Future Past Session", "description": "Test", "timezone": "UTC", "category_id": "3a3a0000-0000-0000-0000-000000000002", "kind_id": "virtual", "starts_at": "2020-01-02T10:00:00", "ends_at": "2020-01-02T12:30:00", "sessions": [{"name": "Future Session", "starts_at": "2020-01-02T10:30:00", "ends_at": "2099-01-02T11:30:00", "kind": "virtual"}]}'::jsonb
    )$$,
    'session ends_at cannot be in the future',
    'Should throw error when past event session ends_at is in the future'
);

-- Should succeed updating live event when starts_at is unchanged
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Live Event Updated',
                'description', 'Updated description',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'in-person',
                'starts_at', to_char((select starts_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'ends_at', to_char((select ends_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
            )
        )$$,
        :'group1ID', :'event9ID', :'category1ID', :'event9ID', :'event9ID'
    ),
    'Should succeed updating live event when starts_at is unchanged'
);

-- Should succeed updating live event when starts_at is moved later (but still in past)
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Live Event Updated Again',
                'description', 'Updated description again',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'in-person',
                'starts_at', to_char((select starts_at from event where event_id = '%s'::uuid) at time zone 'UTC' + interval '30 minutes', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'ends_at', to_char((select ends_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
            )
        )$$,
        :'group1ID', :'event9ID', :'category1ID', :'event9ID', :'event9ID'
    ),
    'Should succeed updating live event when starts_at is moved later (but still in past)'
);

-- Recreate a completed session after the prior live-event updates removed it
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_provider_id,
    meeting_requested
) values (
    :'session3ID',
    :'event9ID',
    'Completed Live Event Session',
    (select starts_at from event where event_id = :'event9ID'),
    current_timestamp - interval '5 minutes',
    'virtual',
    'zoom',
    true
);

-- Should update session recording override when the live event has a completed session
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Live Event Updated With Session Override',
                'description', 'Updated description with completed session override',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'in-person',
                'starts_at', to_char(
                    (select starts_at from event where event_id = '%s'::uuid)
                    at time zone 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS'
                ),
                'ends_at', to_char(
                    (select ends_at from event where event_id = '%s'::uuid)
                    at time zone 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS'
                ),
                'sessions', jsonb_build_array(
                    jsonb_build_object(
                        'session_id', '%s',
                        'name', 'Completed Live Event Session',
                        'starts_at', to_char(
                            (select starts_at from session where session_id = '%s'::uuid)
                            at time zone 'UTC',
                            'YYYY-MM-DD"T"HH24:MI:SS'
                        ),
                        'ends_at', to_char(
                            (select ends_at from session where session_id = '%s'::uuid)
                            at time zone 'UTC',
                            'YYYY-MM-DD"T"HH24:MI:SS'
                        ),
                        'kind', 'virtual',
                        'meeting_provider_id', 'zoom',
                        'meeting_recording_url', 'https://youtube.com/watch?v=live-session-override',
                        'meeting_requested', true
                    )
                )
            )
        )$$,
        :'group1ID',
        :'event9ID',
        :'category1ID',
        :'event9ID',
        :'event9ID',
        :'session3ID',
        :'session3ID',
        :'session3ID'
    ),
    'Should update session recording override when the live event has a completed session'
);
select is(
    (select meeting_recording_url from session where session_id = :'session3ID'::uuid),
    'https://youtube.com/watch?v=live-session-override',
    'Should persist the completed session recording override on a live event update'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
