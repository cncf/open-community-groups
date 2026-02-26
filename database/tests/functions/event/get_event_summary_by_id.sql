-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000041'
\set eventID '00000000-0000-0000-0000-000000000031'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000011'
\set nonExistingEventID '00000000-0000-0000-0000-000000000099'
\set userID '00000000-0000-0000-0000-000000000051'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'communityID', 'event-summary-community', 'Event Summary', 'Community for summary tests', 'https://example.test/logo.png', 'https://example.test/banner_mobile.png', 'https://example.test/banner.png'),
    (:'community2ID', 'other-community', 'Other Community', 'Another community', 'https://example.test/other.png', 'https://example.test/other-banner_mobile.png', 'https://example.test/other-banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name, created_at)
values (:'groupCategoryID', :'communityID', 'Event Category', '2025-01-01 00:00:00');

-- Group
insert into "group" (group_id, community_id, group_category_id, group_site_layout_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'default', 'Summary Group', 'summary-group');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Summary Events');

-- User
insert into "user" (user_id, auth_hash, email, username, email_verified)
values (:'userID', 'test_hash', 'summary-user@example.test', 'summary-user', true);

-- Event
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    timezone,
    venue_city,
    starts_at,
    capacity,
    published_at
) values (
    :'eventID',
    'Event summary test',
    :'eventCategoryID',
    'hybrid',
    :'groupID',
    'Summary Event',
    true,
    'summary-event',
    'America/New_York',
    'Metropolis',
    '2025-07-01 10:00:00+00',
    50,
    '2025-06-01 00:00:00+00'
);

-- Event attendee
insert into event_attendee (event_id, user_id, checked_in, checked_in_at, created_at)
values (:'eventID', :'userID', true, '2025-06-02 00:00:00', '2025-06-02 00:00:00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the same payload as get_event_summary
select is(
    get_event_summary_by_id(:'communityID'::uuid, :'eventID'::uuid)::jsonb,
    get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
    'Should return the same payload as get_event_summary'
);

-- Should return null for missing event
select ok(
    get_event_summary_by_id(:'communityID'::uuid, :'nonExistingEventID'::uuid) is null,
    'Should return null when the event does not exist'
);

-- Should return null when community mismatches
select ok(
    get_event_summary_by_id(:'community2ID'::uuid, :'eventID'::uuid) is null,
    'Should return null when the event belongs to another community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
