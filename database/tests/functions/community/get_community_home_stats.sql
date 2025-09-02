-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set user1ID '00000000-0000-0000-0000-000000000041'
\set user2ID '00000000-0000-0000-0000-000000000042'
\set eventID '00000000-0000-0000-0000-000000000051'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community (for testing home stats)
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
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'seattle.cloudnative.org',
    'Cloud Native Seattle Community',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group category (for organizing groups)
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Groups (for statistics)
insert into "group" (group_id, name, slug, community_id, group_category_id)
values
    (:'group1ID', 'Seattle Kubernetes Meetup', 'seattle-kubernetes-meetup', :'communityID', :'categoryID'),
    (:'group2ID', 'Cloud Native DevOps Group', 'cloud-native-devops-group', :'communityID', :'categoryID');

-- Users (community members)
insert into "user" (user_id, email, username, name, email_verified, auth_hash, community_id, created_at)
values
    (:'user1ID', 'alice@seattle.cloudnative.org', 'alice-member', 'Alice Johnson', false, 'test_hash', :'communityID', '2024-01-01 00:00:00'),
    (:'user2ID', 'bob@seattle.cloudnative.org', 'bob-member', 'Bob Wilson', false, 'test_hash', :'communityID', '2024-01-01 00:00:00');

-- Event category (for organizing events)
insert into event_category (event_category_id, name, slug, community_id)
values ('00000000-0000-0000-0000-000000000061', 'Tech Talks', 'tech-talks', :'communityID');

-- Event (for statistics)
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published
) values (
    :'eventID',
    'KubeCon Seattle 2024',
    'kubecon-seattle-2024',
    'Annual Kubernetes conference',
    'America/Los_Angeles',
    '00000000-0000-0000-0000-000000000061',
    'in-person',
    :'group1ID',
    true
);

-- Group members (for member statistics)
insert into group_member (group_id, user_id, created_at)
values
    (:'group1ID', :'user1ID', '2024-01-01 00:00:00'),
    (:'group1ID', :'user2ID', '2024-01-01 00:00:00'),
    (:'group2ID', :'user1ID', '2024-01-01 00:00:00');

-- Event attendees (for attendee statistics)
insert into event_attendee (event_id, user_id, created_at)
values
    (:'eventID', :'user1ID', '2024-01-01 00:00:00'),
    (:'eventID', :'user2ID', '2024-01-01 00:00:00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Function returns correct community statistics
select is(
    get_community_home_stats('00000000-0000-0000-0000-000000000001'::uuid)::jsonb,
    '{
        "events": 1,
        "groups": 2,
        "groups_members": 3,
        "events_attendees": 2
    }'::jsonb,
    'get_community_home_stats should return correct stats as JSON'
);

-- Function returns zeros for non-existent community
select is(
    get_community_home_stats('00000000-0000-0000-0000-999999999999'::uuid)::jsonb,
    '{
        "events": 0,
        "groups": 0,
        "groups_members": 0,
        "events_attendees": 0
    }'::jsonb,
    'get_community_home_stats with non-existing community should return zeros'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
