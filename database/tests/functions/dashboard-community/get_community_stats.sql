-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set category3ID '00000000-0000-0000-0000-000000000013'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000301'
\set event2ID '00000000-0000-0000-0000-000000000302'
\set event3ID '00000000-0000-0000-0000-000000000303'
\set event4ID '00000000-0000-0000-0000-000000000304'
\set event5ID '00000000-0000-0000-0000-000000000305'
\set event6ID '00000000-0000-0000-0000-000000000306'
\set event7ID '00000000-0000-0000-0000-000000000307'
\set event8ID '00000000-0000-0000-0000-000000000308'
\set eventCategory1ID '00000000-0000-0000-0000-000000000031'
\set eventCategory2ID '00000000-0000-0000-0000-000000000032'
\set group1ID '00000000-0000-0000-0000-000000000101'
\set group2ID '00000000-0000-0000-0000-000000000102'
\set group3ID '00000000-0000-0000-0000-000000000103'
\set group4ID '00000000-0000-0000-0000-000000000104'
\set group5ID '00000000-0000-0000-0000-000000000105'
\set nonExistentCommunityID '00000000-0000-0000-0000-999999999999'
\set region1ID '00000000-0000-0000-0000-000000000021'
\set region2ID '00000000-0000-0000-0000-000000000022'
\set region3ID '00000000-0000-0000-0000-000000000023'
\set user1ID '00000000-0000-0000-0000-000000000201'
\set user2ID '00000000-0000-0000-0000-000000000202'
\set user3ID '00000000-0000-0000-0000-000000000203'
\set user4ID '00000000-0000-0000-0000-000000000204'
\set user5ID '00000000-0000-0000-0000-000000000205'
\set user6ID '00000000-0000-0000-0000-000000000206'
\set user7ID '00000000-0000-0000-0000-000000000207'
\set user8ID '00000000-0000-0000-0000-000000000208'

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
    (:'communityID', 'test-community', 'Test Community', 'test.example.org', 'Test Community', 'Community used for dashboard stats tests', 'https://example.com/logo.png', '{}'::jsonb),
    (:'community2ID', 'other-community', 'Other Community', 'other.example.org', 'Other Community', 'Separate community for isolation testing', 'https://example.com/logo2.png', '{}'::jsonb);

-- Regions
insert into region (region_id, community_id, name, "order") values
    (:'region1ID', :'communityID', 'Europe', 1),
    (:'region2ID', :'communityID', 'North America', 2),
    (:'region3ID', :'community2ID', 'South America', 1);

-- Group categories
insert into group_category (group_category_id, community_id, name) values
    (:'category1ID', :'communityID', 'AI/ML'),
    (:'category2ID', :'communityID', 'Cloud Native'),
    (:'category3ID', :'community2ID', 'Security');

-- Event categories
insert into event_category (event_category_id, community_id, name, slug) values
    (:'eventCategory1ID', :'communityID', 'Conference', 'conference'),
    (:'eventCategory2ID', :'communityID', 'Meetup', 'meetup');

-- Users
insert into "user" (user_id, community_id, auth_hash, email, username) values
    (:'user1ID', :'communityID', 'hash-1', 'user1@example.com', 'user1'),
    (:'user2ID', :'communityID', 'hash-2', 'user2@example.com', 'user2'),
    (:'user3ID', :'communityID', 'hash-3', 'user3@example.com', 'user3'),
    (:'user4ID', :'communityID', 'hash-4', 'user4@example.com', 'user4'),
    (:'user5ID', :'communityID', 'hash-5', 'user5@example.com', 'user5'),
    (:'user6ID', :'communityID', 'hash-6', 'user6@example.com', 'user6'),
    (:'user7ID', :'communityID', 'hash-7', 'user7@example.com', 'user7'),
    (:'user8ID', :'communityID', 'hash-8', 'user8@example.com', 'user8');

-- Groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    created_at,
    region_id,
    active,
    deleted
) values
    (:'group1ID', :'communityID', :'category1ID', 'AI Europe', 'ai-europe', '2024-01-15 00:00:00+00', :'region1ID', true, false),
    (:'group2ID', :'communityID', :'category1ID', 'AI North America', 'ai-north-america', '2024-03-15 00:00:00+00', :'region2ID', true, false),
    (:'group3ID', :'communityID', :'category2ID', 'Cloud Europe', 'cloud-europe', '2024-05-15 00:00:00+00', :'region1ID', true, false),
    (:'group4ID', :'communityID', :'category2ID', 'Cloud North America', 'cloud-north-america', '2024-07-15 00:00:00+00', :'region2ID', true, false),
    (:'group5ID', :'community2ID', :'category3ID', 'Other Community Group', 'other-group', '2024-09-15 00:00:00+00', :'region3ID', true, false);

-- Group members
insert into group_member (group_id, user_id, created_at) values
    (:'group1ID', :'user1ID', '2024-01-20 00:00:00+00'),
    (:'group1ID', :'user2ID', '2024-02-10 00:00:00+00'),
    (:'group1ID', :'user3ID', '2024-06-05 00:00:00+00'),
    (:'group2ID', :'user4ID', '2024-03-20 00:00:00+00'),
    (:'group2ID', :'user5ID', '2024-04-10 00:00:00+00'),
    (:'group3ID', :'user6ID', '2024-05-20 00:00:00+00'),
    (:'group3ID', :'user7ID', '2024-08-10 00:00:00+00'),
    (:'group4ID', :'user8ID', '2024-07-20 00:00:00+00');

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
    (:'event1ID', :'group1ID', :'eventCategory1ID', 'in-person', 'Conference 1', 'conference-1', 'Event 1', 'UTC', true, false, false, '2024-02-15 00:00:00+00'),
    (:'event2ID', :'group1ID', :'eventCategory2ID', 'in-person', 'Meetup 1', 'meetup-1', 'Event 2', 'UTC', true, false, false, '2024-04-15 00:00:00+00'),
    (:'event3ID', :'group2ID', :'eventCategory1ID', 'in-person', 'Conference 2', 'conference-2', 'Event 3', 'UTC', true, false, false, '2024-06-15 00:00:00+00'),
    (:'event4ID', :'group3ID', :'eventCategory2ID', 'in-person', 'Meetup 2', 'meetup-2', 'Event 4', 'UTC', true, false, false, '2024-08-15 00:00:00+00'),
    (:'event5ID', :'group3ID', :'eventCategory1ID', 'in-person', 'Conference 3', 'conference-3', 'Event 5', 'UTC', true, false, false, '2024-09-15 00:00:00+00'),
    (:'event6ID', :'group4ID', :'eventCategory2ID', 'in-person', 'Meetup 3', 'meetup-3', 'Event 6', 'UTC', true, false, false, '2024-10-15 00:00:00+00'),
    (:'event7ID', :'group1ID', :'eventCategory1ID', 'in-person', 'Conference Draft', 'conference-draft', 'Draft Event', 'UTC', false, false, false, '2024-11-15 00:00:00+00'),
    (:'event8ID', :'group2ID', :'eventCategory2ID', 'in-person', 'Meetup Canceled', 'meetup-canceled', 'Canceled Event', 'UTC', false, true, false, '2024-12-15 00:00:00+00');

-- Event attendees
insert into event_attendee (event_id, user_id, created_at) values
    (:'event1ID', :'user1ID', '2024-02-01 00:00:00+00'),
    (:'event1ID', :'user2ID', '2024-02-05 00:00:00+00'),
    (:'event1ID', :'user3ID', '2024-02-10 00:00:00+00'),
    (:'event2ID', :'user4ID', '2024-04-01 00:00:00+00'),
    (:'event2ID', :'user5ID', '2024-04-05 00:00:00+00'),
    (:'event3ID', :'user6ID', '2024-06-01 00:00:00+00'),
    (:'event3ID', :'user7ID', '2024-06-05 00:00:00+00'),
    (:'event4ID', :'user8ID', '2024-08-01 00:00:00+00'),
    (:'event5ID', :'user1ID', '2024-09-01 00:00:00+00'),
    (:'event5ID', :'user2ID', '2024-09-05 00:00:00+00'),
    (:'event6ID', :'user3ID', '2024-10-01 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return complete accurate JSON for test community
select is(
    get_community_stats(:'communityID'::uuid)::jsonb,
    $$
    {
        "groups": {
            "total": 4,
            "total_by_category": [
                ["AI/ML", 2],
                ["Cloud Native", 2]
            ],
            "total_by_region": [
                ["Europe", 2],
                ["North America", 2]
            ],
            "running_total": [
                [1704067200000, 1],
                [1709251200000, 2],
                [1714521600000, 3],
                [1719792000000, 4]
            ],
            "running_total_by_category": {
                "AI/ML": [
                    [1704067200000, 1],
                    [1709251200000, 2]
                ],
                "Cloud Native": [
                    [1714521600000, 1],
                    [1719792000000, 2]
                ]
            },
            "running_total_by_region": {
                "Europe": [
                    [1704067200000, 1],
                    [1714521600000, 2]
                ],
                "North America": [
                    [1709251200000, 1],
                    [1719792000000, 2]
                ]
            },
            "per_month": [
                ["2024-01", 1],
                ["2024-03", 1],
                ["2024-05", 1],
                ["2024-07", 1]
            ],
            "per_month_by_category": {
                "AI/ML": [
                    ["2024-01", 1],
                    ["2024-03", 1]
                ],
                "Cloud Native": [
                    ["2024-05", 1],
                    ["2024-07", 1]
                ]
            },
            "per_month_by_region": {
                "Europe": [
                    ["2024-01", 1],
                    ["2024-05", 1]
                ],
                "North America": [
                    ["2024-03", 1],
                    ["2024-07", 1]
                ]
            }
        },
        "members": {
            "total": 8,
            "total_by_category": [
                ["AI/ML", 5],
                ["Cloud Native", 3]
            ],
            "total_by_region": [
                ["Europe", 5],
                ["North America", 3]
            ],
            "running_total": [
                [1704067200000, 1],
                [1706745600000, 2],
                [1709251200000, 3],
                [1711929600000, 4],
                [1714521600000, 5],
                [1717200000000, 6],
                [1719792000000, 7],
                [1722470400000, 8]
            ],
            "running_total_by_category": {
                "AI/ML": [
                    [1704067200000, 1],
                    [1706745600000, 2],
                    [1709251200000, 3],
                    [1711929600000, 4],
                    [1717200000000, 5]
                ],
                "Cloud Native": [
                    [1714521600000, 1],
                    [1719792000000, 2],
                    [1722470400000, 3]
                ]
            },
            "running_total_by_region": {
                "Europe": [
                    [1704067200000, 1],
                    [1706745600000, 2],
                    [1714521600000, 3],
                    [1717200000000, 4],
                    [1722470400000, 5]
                ],
                "North America": [
                    [1709251200000, 1],
                    [1711929600000, 2],
                    [1719792000000, 3]
                ]
            },
            "per_month": [
                ["2024-01", 1],
                ["2024-02", 1],
                ["2024-03", 1],
                ["2024-04", 1],
                ["2024-05", 1],
                ["2024-06", 1],
                ["2024-07", 1],
                ["2024-08", 1]
            ],
            "per_month_by_category": {
                "AI/ML": [
                    ["2024-01", 1],
                    ["2024-02", 1],
                    ["2024-03", 1],
                    ["2024-04", 1],
                    ["2024-06", 1]
                ],
                "Cloud Native": [
                    ["2024-05", 1],
                    ["2024-07", 1],
                    ["2024-08", 1]
                ]
            },
            "per_month_by_region": {
                "Europe": [
                    ["2024-01", 1],
                    ["2024-02", 1],
                    ["2024-05", 1],
                    ["2024-06", 1],
                    ["2024-08", 1]
                ],
                "North America": [
                    ["2024-03", 1],
                    ["2024-04", 1],
                    ["2024-07", 1]
                ]
            }
        },
        "events": {
            "total": 6,
            "total_by_event_category": [
                ["Conference", 3],
                ["Meetup", 3]
            ],
            "total_by_group_category": [
                ["AI/ML", 3],
                ["Cloud Native", 3]
            ],
            "total_by_group_region": [
                ["Europe", 4],
                ["North America", 2]
            ],
            "running_total": [
                [1706745600000, 1],
                [1711929600000, 2],
                [1717200000000, 3],
                [1722470400000, 4],
                [1725148800000, 5],
                [1727740800000, 6]
            ],
            "running_total_by_event_category": {
                "Conference": [
                    [1706745600000, 1],
                    [1717200000000, 2],
                    [1725148800000, 3]
                ],
                "Meetup": [
                    [1711929600000, 1],
                    [1722470400000, 2],
                    [1727740800000, 3]
                ]
            },
            "running_total_by_group_category": {
                "AI/ML": [
                    [1706745600000, 1],
                    [1711929600000, 2],
                    [1717200000000, 3]
                ],
                "Cloud Native": [
                    [1722470400000, 1],
                    [1725148800000, 2],
                    [1727740800000, 3]
                ]
            },
            "running_total_by_group_region": {
                "Europe": [
                    [1706745600000, 1],
                    [1711929600000, 2],
                    [1722470400000, 3],
                    [1725148800000, 4]
                ],
                "North America": [
                    [1717200000000, 1],
                    [1727740800000, 2]
                ]
            },
            "per_month": [
                ["2024-02", 1],
                ["2024-04", 1],
                ["2024-06", 1],
                ["2024-08", 1],
                ["2024-09", 1],
                ["2024-10", 1]
            ],
            "per_month_by_event_category": {
                "Conference": [
                    ["2024-02", 1],
                    ["2024-06", 1],
                    ["2024-09", 1]
                ],
                "Meetup": [
                    ["2024-04", 1],
                    ["2024-08", 1],
                    ["2024-10", 1]
                ]
            },
            "per_month_by_group_category": {
                "AI/ML": [
                    ["2024-02", 1],
                    ["2024-04", 1],
                    ["2024-06", 1]
                ],
                "Cloud Native": [
                    ["2024-08", 1],
                    ["2024-09", 1],
                    ["2024-10", 1]
                ]
            },
            "per_month_by_group_region": {
                "Europe": [
                    ["2024-02", 1],
                    ["2024-04", 1],
                    ["2024-08", 1],
                    ["2024-09", 1]
                ],
                "North America": [
                    ["2024-06", 1],
                    ["2024-10", 1]
                ]
            }
        },
        "attendees": {
            "total": 11,
            "total_by_event_category": [
                ["Conference", 7],
                ["Meetup", 4]
            ],
            "total_by_group_category": [
                ["AI/ML", 7],
                ["Cloud Native", 4]
            ],
            "total_by_group_region": [
                ["Europe", 8],
                ["North America", 3]
            ],
            "running_total": [
                [1706745600000, 3],
                [1711929600000, 5],
                [1717200000000, 7],
                [1722470400000, 8],
                [1725148800000, 10],
                [1727740800000, 11]
            ],
            "running_total_by_event_category": {
                "Conference": [
                    [1706745600000, 3],
                    [1717200000000, 5],
                    [1725148800000, 7]
                ],
                "Meetup": [
                    [1711929600000, 2],
                    [1722470400000, 3],
                    [1727740800000, 4]
                ]
            },
            "running_total_by_group_category": {
                "AI/ML": [
                    [1706745600000, 3],
                    [1711929600000, 5],
                    [1717200000000, 7]
                ],
                "Cloud Native": [
                    [1722470400000, 1],
                    [1725148800000, 3],
                    [1727740800000, 4]
                ]
            },
            "running_total_by_group_region": {
                "Europe": [
                    [1706745600000, 3],
                    [1711929600000, 5],
                    [1722470400000, 6],
                    [1725148800000, 8]
                ],
                "North America": [
                    [1717200000000, 2],
                    [1727740800000, 3]
                ]
            },
            "per_month": [
                ["2024-02", 3],
                ["2024-04", 2],
                ["2024-06", 2],
                ["2024-08", 1],
                ["2024-09", 2],
                ["2024-10", 1]
            ],
            "per_month_by_event_category": {
                "Conference": [
                    ["2024-02", 3],
                    ["2024-06", 2],
                    ["2024-09", 2]
                ],
                "Meetup": [
                    ["2024-04", 2],
                    ["2024-08", 1],
                    ["2024-10", 1]
                ]
            },
            "per_month_by_group_category": {
                "AI/ML": [
                    ["2024-02", 3],
                    ["2024-04", 2],
                    ["2024-06", 2]
                ],
                "Cloud Native": [
                    ["2024-08", 1],
                    ["2024-09", 2],
                    ["2024-10", 1]
                ]
            },
            "per_month_by_group_region": {
                "Europe": [
                    ["2024-02", 3],
                    ["2024-04", 2],
                    ["2024-08", 1],
                    ["2024-09", 2]
                ],
                "North America": [
                    ["2024-06", 2],
                    ["2024-10", 1]
                ]
            }
        }
    }
    $$::jsonb,
    'Should return complete accurate JSON for test community'
);

-- Should return empty stats for unknown community
select is(
    get_community_stats(:'nonExistentCommunityID'::uuid)::jsonb,
    $$
    {
        "groups": {
            "total": 0,
            "total_by_category": [],
            "total_by_region": [],
            "running_total": [],
            "running_total_by_category": {},
            "running_total_by_region": {},
            "per_month": [],
            "per_month_by_category": {},
            "per_month_by_region": {}
        },
        "members": {
            "total": 0,
            "total_by_category": [],
            "total_by_region": [],
            "running_total": [],
            "running_total_by_category": {},
            "running_total_by_region": {},
            "per_month": [],
            "per_month_by_category": {},
            "per_month_by_region": {}
        },
        "events": {
            "total": 0,
            "total_by_event_category": [],
            "total_by_group_category": [],
            "total_by_group_region": [],
            "running_total": [],
            "running_total_by_event_category": {},
            "running_total_by_group_category": {},
            "running_total_by_group_region": {},
            "per_month": [],
            "per_month_by_event_category": {},
            "per_month_by_group_category": {},
            "per_month_by_group_region": {}
        },
        "attendees": {
            "total": 0,
            "total_by_event_category": [],
            "total_by_group_category": [],
            "total_by_group_region": [],
            "running_total": [],
            "running_total_by_event_category": {},
            "running_total_by_group_category": {},
            "running_total_by_group_region": {},
            "per_month": [],
            "per_month_by_event_category": {},
            "per_month_by_group_category": {},
            "per_month_by_group_region": {}
        }
    }
    $$::jsonb,
    'Should return empty stats for unknown community'
);

-- Should only count groups from the requested community
select is(
    (get_community_stats(:'communityID'::uuid)::jsonb->'groups'->>'total')::int,
    4,
    'Should only count groups from the requested community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
