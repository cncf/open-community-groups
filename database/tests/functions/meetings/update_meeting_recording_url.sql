-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventID '00000000-0000-0000-0000-000000000101'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000002'
\set meetingID '00000000-0000-0000-0000-000000000301'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

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

-- Should set recording_url when updating
select update_meeting_recording_url('zoom', '123456789', 'https://zoom.us/rec/share/abc123');
select is(
    (select recording_url from meeting where meeting_id = :'meetingID'),
    'https://zoom.us/rec/share/abc123',
    'Recording URL updated successfully'
);

-- Should set updated_at after recording URL update
select isnt(
    (select updated_at from meeting where meeting_id = :'meetingID'),
    null,
    'updated_at is set after recording URL update'
);

-- Should overwrite recording URL when updating with different URL
select update_meeting_recording_url('zoom', '123456789', 'https://zoom.us/rec/share/xyz789');
select is(
    (select recording_url from meeting where meeting_id = :'meetingID'),
    'https://zoom.us/rec/share/xyz789',
    'Recording URL can be updated with a new value'
);

-- Should not raise error when updating non-existent meeting
select lives_ok(
    $$ select update_meeting_recording_url('zoom', 'nonexistent', 'https://example.com/rec') $$,
    'Updating non-existent meeting does not raise error'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
