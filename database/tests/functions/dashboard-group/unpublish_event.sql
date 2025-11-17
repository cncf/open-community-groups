-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set eventID '00000000-0000-0000-0000-000000000031'
\set userID '00000000-0000-0000-0000-000000000041'

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
    'test.localhost',
    'Test Community',
    'A test community',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'General', 'general', :'communityID');

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

-- User (as previously published_by)
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    username
) values (
    :'userID',
    'x',
    :'communityID',
    'user@test.local',
    'user'
);

-- Event (published)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    published_at,
    published_by
) values (
    :'eventID',
    :'groupID',
    'Test Event',
    'test-event',
    'A test event',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    now(),
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: unpublish_event should clear published flags and metadata
select unpublish_event(:'groupID'::uuid, :'eventID'::uuid);

select is(
    (select published from event where event_id = :'eventID'),
    false,
    'unpublish_event should set published=false'
);

select is(
    (select published_at from event where event_id = :'eventID'),
    null,
    'unpublish_event should set published_at to null'
);

select is(
    (select published_by from event where event_id = :'eventID'),
    null,
    'unpublish_event should set published_by to null'
);

-- Test: unpublish_event should throw error when group_id does not match
select throws_ok(
    $$select unpublish_event('00000000-0000-0000-0000-000000000099'::uuid, '00000000-0000-0000-0000-000000000031'::uuid)$$,
    'P0001',
    'event not found or inactive',
    'unpublish_event should throw error when group_id does not match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
