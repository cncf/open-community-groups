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
\set event1ID '00000000-0000-0000-0000-000000000301'
\set event2ID '00000000-0000-0000-0000-000000000302'
\set event3ID '00000000-0000-0000-0000-000000000303'
\set eventCategory2ID '00000000-0000-0000-0000-000000000202'
\set eventCategoryID '00000000-0000-0000-0000-000000000201'
\set group1ID '00000000-0000-0000-0000-000000000101'
\set group2ID '00000000-0000-0000-0000-000000000102'
\set group3ID '00000000-0000-0000-0000-000000000103'
\set groupCategory2ID '00000000-0000-0000-0000-000000000502'
\set groupCategoryID '00000000-0000-0000-0000-000000000501'
\set nonExistentGroupID '00000000-0000-0000-0000-999999999999'
\set user1ID '00000000-0000-0000-0000-000000000401'
\set user2ID '00000000-0000-0000-0000-000000000402'
\set user3ID '00000000-0000-0000-0000-000000000403'
\set user4ID '00000000-0000-0000-0000-000000000404'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_url
) values
    (:'communityID', 'test-community', 'Test Community', 'Community used for group stats tests', 'https://example.com/logo.png', 'https://example.com/banner.png'),
    (:'community2ID', 'other-community', 'Other Community', 'Separate community for isolation testing', 'https://example.com/logo2.png', 'https://example.com/banner2.png');

-- Group categories
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Tech'),
    (:'groupCategory2ID', :'community2ID', 'Tech2');

-- Event categories
insert into event_category (event_category_id, community_id, name, slug) values
    (:'eventCategoryID', :'communityID', 'Conference', 'conference'),
    (:'eventCategory2ID', :'community2ID', 'Conference2', 'conference2');

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
    (:'group1ID', :'communityID', :'groupCategoryID', 'Group One', 'group-one',
        '2025-09-01 00:00:00+00', true, false),
    (:'group2ID', :'communityID', :'groupCategoryID', 'Group Two', 'group-two',
        '2025-10-01 00:00:00+00', true, false),
    (:'group3ID', :'community2ID', :'groupCategory2ID', 'Other Community Group', 'other-group',
        '2025-11-01 00:00:00+00', true, false);

-- Users
insert into "user" (user_id, auth_hash, email, username) values
    (:'user1ID', 'hash-1', 'user1@example.com', 'user1'),
    (:'user2ID', 'hash-2', 'user2@example.com', 'user2'),
    (:'user3ID', 'hash-3', 'user3@example.com', 'user3'),
    (:'user4ID', 'hash-4', 'user4@example.com', 'user4');

-- Members
insert into group_member (group_id, user_id, created_at) values
    (:'group1ID', :'user1ID', '2025-10-05 00:00:00+00'),
    (:'group1ID', :'user2ID', '2025-12-10 00:00:00+00'),
    (:'group2ID', :'user3ID', '2025-12-15 00:00:00+00');

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
    (:'event1ID', :'group1ID', :'eventCategoryID', 'in-person', 'Event One', 'event-one',
        'First event', 'UTC', true, false, false, '2025-11-15 00:00:00+00'),
    (:'event2ID', :'group1ID', :'eventCategoryID', 'in-person', 'Event Two', 'event-two',
        'Second event', 'UTC', true, false, false, '2026-01-15 00:00:00+00'),
    (:'event3ID', :'group3ID', :'eventCategory2ID', 'in-person', 'Other Group Event', 'other-event',
        'Other group event', 'UTC', true, false, false, '2026-01-20 00:00:00+00');

-- Attendees
insert into event_attendee (event_id, user_id, created_at) values
    (:'event1ID', :'user1ID', '2025-11-01 00:00:00+00'),
    (:'event1ID', :'user2ID', '2025-11-05 00:00:00+00'),
    (:'event2ID', :'user1ID', '2026-01-10 00:00:00+00'),
    (:'event3ID', :'user4ID', '2026-01-20 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return complete accurate JSON for seeded group
select is(
    get_group_stats(:'communityID'::uuid, :'group1ID'::uuid)::jsonb,
    $$
    {
        "members": {
            "total": 2,
            "running_total": [
                [1759276800000, 1],
                [1764547200000, 2]
            ],
            "per_month": [
                ["2025-10", 1],
                ["2025-12", 1]
            ]
        },
        "events": {
            "total": 2,
            "running_total": [
                [1761955200000, 1],
                [1767225600000, 2]
            ],
            "per_month": [
                ["2025-11", 1],
                ["2026-01", 1]
            ]
        },
        "attendees": {
            "total": 3,
            "running_total": [
                [1761955200000, 2],
                [1767225600000, 3]
            ],
            "per_month": [
                ["2025-11", 2],
                ["2026-01", 1]
            ]
        }
    }
    $$,
    'Should return complete accurate JSON for seeded group'
);

-- Should return empty stats for unknown group
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
    'Should return empty stats for unknown group'
);

-- Should only count events from the requested group
select is(
    (get_group_stats(:'communityID'::uuid, :'group1ID'::uuid)::jsonb->'events'->>'total')::int,
    2,
    'Should only count events from the requested group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
