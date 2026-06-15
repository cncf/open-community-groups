-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a0f0000-0000-0000-0000-000000000001'
\set event1ID '3a0f0000-0000-0000-0000-000000000002'
\set event2ID '3a0f0000-0000-0000-0000-000000000003'
\set eventCategoryID '3a0f0000-0000-0000-0000-000000000004'
\set groupCategoryID '3a0f0000-0000-0000-0000-000000000005'
\set groupID '3a0f0000-0000-0000-0000-000000000006'
\set user1ID '3a0f0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A community for cloud native technologies',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- User
insert into "user" (user_id, email, username, auth_hash, name)
values (:'user1ID', 'creator@example.com', 'creator', 'hash', 'Creator User');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'Conference', :'communityID');

-- Group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    active
) values (
    :'groupID',
    'Seattle Kubernetes Meetup',
    'seattle-kubernetes',
    :'communityID',
    :'groupCategoryID',
    true
);

-- Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    event_category_id,
    event_kind_id,
    timezone,

    created_by
) values (
    :'event1ID',
    :'groupID',
    'Created Event',
    'created-event',
    'An event with creator metadata',
    :'eventCategoryID',
    'in-person',
    'America/New_York',

    :'user1ID'
), (
    :'event2ID',
    :'groupID',
    'Untracked Event',
    'untracked-event',
    'An event without creator metadata',
    :'eventCategoryID',
    'virtual',
    'America/New_York',

    null
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should extend the shared event summary with dashboard information
select is(
    get_event_summary_dashboard(:'communityID'::uuid, :'groupID'::uuid, :'event1ID'::uuid)::jsonb,
    get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event1ID'::uuid)::jsonb
        || jsonb_build_object(
            'created_by_display_name', 'Creator User',
            'created_by_username', 'creator'
        ),
    'Should extend the shared event summary with dashboard information'
);

-- Should match the shared event summary when dashboard information is unavailable
select is(
    get_event_summary_dashboard(:'communityID'::uuid, :'groupID'::uuid, :'event2ID'::uuid)::jsonb,
    get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event2ID'::uuid)::jsonb,
    'Should match the shared event summary when dashboard information is unavailable'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
