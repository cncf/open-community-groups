-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set communityID '00000000-0000-0000-0000-000000000001'
\set otherCommunityID '00000000-0000-0000-0000-000000000002'
\set groupID '00000000-0000-0000-0000-000000000101'
\set otherGroupID '00000000-0000-0000-0000-000000000102'
\set otherCommunityGroupID '00000000-0000-0000-0000-000000000103'
\set nonExistentGroupID '00000000-0000-0000-0000-999999999999'
\set eventCategoryID '00000000-0000-0000-0000-000000000201'
\set event1ID '00000000-0000-0000-0000-000000000301'
\set event2ID '00000000-0000-0000-0000-000000000302'
\set eventOtherGroupID '00000000-0000-0000-0000-000000000303'
\set user1ID '00000000-0000-0000-0000-000000000401'
\set user2ID '00000000-0000-0000-0000-000000000402'
\set userOtherID '00000000-0000-0000-0000-000000000403'
\set groupCategoryID '00000000-0000-0000-0000-000000000501'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values
    (
        :'communityID',
        'test-community',
        'Test Community',
        'test.example.org',
        'Test Community',
        'Community used for group stats tests',
        'https://example.com/logo.png',
        '{}'::jsonb
    ),
    (
        :'otherCommunityID',
        'other-community',
        'Other Community',
        'other.example.org',
        'Other Community',
        'Separate community for isolation testing',
        'https://example.com/logo2.png',
        '{}'::jsonb
    );

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name, slug)
values (:'eventCategoryID', :'communityID', 'Conference', 'conference');

-- Groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    created_at,
    active,
    deleted
) values
    (:'groupID', :'communityID', :'groupCategoryID', 'Group One', 'group-one', '2024-01-01 00:00:00+00', true, false),
    (:'otherGroupID', :'communityID', :'groupCategoryID', 'Group Two', 'group-two', '2024-02-01 00:00:00+00', true, false),
    (:'otherCommunityGroupID', :'otherCommunityID', :'groupCategoryID', 'Other Community Group', 'other-group', '2024-03-01 00:00:00+00', true, false);

-- Users
insert into "user" (user_id, community_id, auth_hash, email, username) values
    (:'user1ID', :'communityID', 'hash-1', 'user1@example.com', 'user1'),
    (:'user2ID', :'communityID', 'hash-2', 'user2@example.com', 'user2'),
    (:'userOtherID', :'communityID', 'hash-3', 'user3@example.com', 'user3');

-- Members
insert into group_member (group_id, user_id, created_at) values
    (:'groupID', :'user1ID', '2024-01-05 00:00:00+00'),
    (:'groupID', :'user2ID', '2024-03-10 00:00:00+00'),
    (:'otherGroupID', :'userOtherID', '2024-04-01 00:00:00+00');

-- Events
insert into event (
    event_id,
    group_id,
    event_category_id,
    event_kind_id,
    name,
    slug,
    description,
    timezone,
    published,
    canceled,
    deleted,
    starts_at
) values
    (:'event1ID', :'groupID', :'eventCategoryID', 'in-person', 'Event One', 'event-one', 'First event', 'UTC', true, false, false, '2024-02-15 00:00:00+00'),
    (:'event2ID', :'groupID', :'eventCategoryID', 'in-person', 'Event Two', 'event-two', 'Second event', 'UTC', true, false, false, '2024-04-15 00:00:00+00'),
    (:'eventOtherGroupID', :'otherGroupID', :'eventCategoryID', 'in-person', 'Other Group Event', 'other-event', 'Other group event', 'UTC', true, false, false, '2024-05-15 00:00:00+00');

-- Attendees
insert into event_attendee (event_id, user_id, created_at) values
    (:'event1ID', :'user1ID', '2024-02-01 00:00:00+00'),
    (:'event1ID', :'user2ID', '2024-02-05 00:00:00+00'),
    (:'event2ID', :'user1ID', '2024-04-10 00:00:00+00'),
    (:'eventOtherGroupID', :'userOtherID', '2024-05-20 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: get_group_stats should return complete accurate JSON for seeded group
select is(
    get_group_stats(:'communityID'::uuid, :'groupID'::uuid)::jsonb,
    $$
    {
        "members": {
            "total": 2,
            "running_total": [
                [1704067200000, 1],
                [1709251200000, 2]
            ],
            "per_month": [
                ["2024-01", 1],
                ["2024-03", 1]
            ]
        },
        "events": {
            "total": 2,
            "running_total": [
                [1706745600000, 1],
                [1711929600000, 2]
            ],
            "per_month": [
                ["2024-02", 1],
                ["2024-04", 1]
            ]
        },
        "attendees": {
            "total": 3,
            "running_total": [
                [1706745600000, 2],
                [1711929600000, 3]
            ],
            "per_month": [
                ["2024-02", 2],
                ["2024-04", 1]
            ]
        }
    }
    $$,
    'get_group_stats should return complete accurate JSON for seeded group'
);

-- Test: get_group_stats should return empty stats for unknown group
select is(
    get_group_stats(:'communityID'::uuid, :'nonExistentGroupID'::uuid)::jsonb,
    $$
    {
        "members": {
            "total": 0,
            "running_total": [],
            "per_month": []
        },
        "events": {
            "total": 0,
            "running_total": [],
            "per_month": []
        },
        "attendees": {
            "total": 0,
            "running_total": [],
            "per_month": []
        }
    }
    $$,
    'get_group_stats should return empty stats for unknown group'
);

-- Test: get_group_stats should ignore data from other groups and communities
select is(
    (get_group_stats(:'communityID'::uuid, :'groupID'::uuid)::jsonb->'events'->>'total')::int,
    2,
    'get_group_stats should only count events from the requested group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
