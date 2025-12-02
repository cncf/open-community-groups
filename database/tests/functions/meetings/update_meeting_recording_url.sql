-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000002'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set eventID '00000000-0000-0000-0000-000000000101'
\set meetingID '00000000-0000-0000-0000-000000000301'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'test.example.org',
    'Test Community',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'categoryID', 'Conference', 'conference', :'communityID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Group
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'communityID',
    'Test Group',
    'test-group',
    'A test group',
    :'groupCategoryID'
);

-- Event
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
    :'eventID',
    :'groupID',
    'Event Test',
    'event-test',
    'Test event for recording URL update',
    'America/New_York',
    :'categoryID',
    'virtual',
    '2025-06-01 10:00:00-04',
    '2025-06-01 11:00:00-04'
);

-- Meeting linked to event
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingID', :'eventID', 'zoom', '123456789', 'https://zoom.us/j/123456789');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test 1: Update recording URL - verify recording_url is set
select update_meeting_recording_url('zoom', '123456789', 'https://zoom.us/rec/share/abc123');
select is(
    (select recording_url from meeting where meeting_id = :'meetingID'),
    'https://zoom.us/rec/share/abc123',
    'Recording URL updated successfully'
);

-- Test 2: Update recording URL - verify updated_at is set
select isnt(
    (select updated_at from meeting where meeting_id = :'meetingID'),
    null,
    'updated_at is set after recording URL update'
);

-- Test 3: Update with different URL - verify URL is overwritten
select update_meeting_recording_url('zoom', '123456789', 'https://zoom.us/rec/share/xyz789');
select is(
    (select recording_url from meeting where meeting_id = :'meetingID'),
    'https://zoom.us/rec/share/xyz789',
    'Recording URL can be updated with a new value'
);

-- Test 4: Update non-existent meeting - should not raise error
select lives_ok(
    $$ select update_meeting_recording_url('zoom', 'nonexistent', 'https://example.com/rec') $$,
    'Updating non-existent meeting does not raise error'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
