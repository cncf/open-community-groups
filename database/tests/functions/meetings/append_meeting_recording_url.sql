-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a020000-0000-0000-0000-000000000001'
\set eventCategoryID '7a020000-0000-0000-0000-000000000002'
\set eventID '7a020000-0000-0000-0000-000000000003'
\set groupCategoryID '7a020000-0000-0000-0000-000000000004'
\set groupID '7a020000-0000-0000-0000-000000000005'
\set meetingID '7a020000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event Category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Conference');

-- Group Category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'A test group'
);

-- Event
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
    timezone
) values (
    :'eventID',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Event Test',
    'event-test',
    'Test event for recording URL update',
    '2025-06-01 10:00:00-04',
    '2025-06-01 11:00:00-04',
    'America/New_York'
);

-- Meeting linked to event
insert into meeting (meeting_id, event_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'meetingID', :'eventID', 'zoom', '123456789', 'https://zoom.us/j/123456789');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should append recording URL
select lives_ok(
    $$select append_meeting_recording_url('zoom', '123456789', 'https://zoom.us/rec/share/abc123')$$,
    'Should append recording URL'
);
select results_eq(
    format(
        $$select recording_urls from meeting where meeting_id = %L::uuid$$,
        :'meetingID'
    ),
    $$ values (array['https://zoom.us/rec/share/abc123']::text[]) $$,
    'Recording URL appended successfully'
);

-- Should set updated_at after recording URL update
select isnt(
    (select updated_at from meeting where meeting_id = :'meetingID'),
    null,
    'updated_at is set after recording URL update'
);

update event
set meeting_recording_published = false
where event_id = :'eventID';

-- Should append distinct recording URL
select lives_ok(
    $$select append_meeting_recording_url('zoom', '123456789', 'https://zoom.us/rec/share/xyz789')$$,
    'Should append distinct recording URL'
);
select results_eq(
    format(
        $$select recording_urls from meeting where meeting_id = %L::uuid$$,
        :'meetingID'
    ),
    $$ values (array['https://zoom.us/rec/share/abc123', 'https://zoom.us/rec/share/xyz789']::text[]) $$,
    'Distinct recording URL is appended'
);
select is(
    (select meeting_recording_published from event where event_id = :'eventID'),
    false,
    'Recording visibility is not changed by provider recording updates'
);

-- Should not append duplicate recording URL
select lives_ok(
    $$select append_meeting_recording_url('zoom', '123456789', 'https://zoom.us/rec/share/abc123')$$,
    'Should accept duplicate recording URL update'
);
select results_eq(
    format(
        $$select recording_urls from meeting where meeting_id = %L::uuid$$,
        :'meetingID'
    ),
    $$ values (array['https://zoom.us/rec/share/abc123', 'https://zoom.us/rec/share/xyz789']::text[]) $$,
    'Duplicate recording URL is not appended'
);

-- Should not append blank recording URL
select lives_ok(
    $$select append_meeting_recording_url('zoom', '123456789', '   ')$$,
    'Should accept blank recording URL update'
);
select results_eq(
    format(
        $$select recording_urls from meeting where meeting_id = %L::uuid$$,
        :'meetingID'
    ),
    $$ values (array['https://zoom.us/rec/share/abc123', 'https://zoom.us/rec/share/xyz789']::text[]) $$,
    'Blank recording URL is not appended'
);

-- Should not raise error when updating non-existent meeting
select lives_ok(
    $$ select append_meeting_recording_url('zoom', 'nonexistent', 'https://example.com/rec') $$,
    'Updating non-existent meeting does not raise error'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
