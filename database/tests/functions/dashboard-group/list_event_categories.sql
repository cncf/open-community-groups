-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values
    (:'community1ID', 'cloud-native-seattle', 'Cloud Native Seattle', 'A vibrant community for cloud native technologies and practices in Seattle', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png'),
    (:'community2ID', 'devops-vancouver', 'DevOps Vancouver', 'Building DevOps expertise and community in Vancouver', 'https://example.com/logo2.png', 'https://example.com/banner_mobile2.png', 'https://example.com/banner2.png');

-- Event Category
insert into event_category (event_category_id, name, community_id, "order")
values
    ('00000000-0000-0000-0000-000000000011', 'Workshop', :'community1ID', 2),
    ('00000000-0000-0000-0000-000000000012', 'Conference', :'community1ID', 1),
    ('00000000-0000-0000-0000-000000000013', 'Meetup', :'community1ID', null);

-- Event Category (other community)
insert into event_category (event_category_id, name, community_id)
values
    ('00000000-0000-0000-0000-000000000014', 'Seminar', :'community2ID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values
    ('00000000-0000-0000-0000-000000000021', 'Technology', :'community1ID'),
    ('00000000-0000-0000-0000-000000000022', 'Business', :'community2ID');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug)
values
    (
        '00000000-0000-0000-0000-000000000031',
        :'community1ID',
        '00000000-0000-0000-0000-000000000021',
        'Kubernetes Seattle',
        'kubernetes-seattle'
    ),
    (
        '00000000-0000-0000-0000-000000000032',
        :'community2ID',
        '00000000-0000-0000-0000-000000000022',
        'DevOps Vancouver',
        'devops-vancouver'
    );

-- Events
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
)
values
    (
        '00000000-0000-0000-0000-000000000041',
        'Conference opening day',
        '00000000-0000-0000-0000-000000000012',
        'in-person',
        '00000000-0000-0000-0000-000000000031',
        'Conference Day 1',
        'conference-day-1',
        'UTC'
    ),
    (
        '00000000-0000-0000-0000-000000000042',
        'Conference deep-dive sessions',
        '00000000-0000-0000-0000-000000000012',
        'in-person',
        '00000000-0000-0000-0000-000000000031',
        'Conference Day 2',
        'conference-day-2',
        'UTC'
    ),
    (
        '00000000-0000-0000-0000-000000000043',
        'Workshop hands-on labs',
        '00000000-0000-0000-0000-000000000011',
        'virtual',
        '00000000-0000-0000-0000-000000000031',
        'Workshop Lab',
        'workshop-lab',
        'UTC'
    ),
    (
        '00000000-0000-0000-0000-000000000044',
        'Seminar keynote',
        '00000000-0000-0000-0000-000000000014',
        'hybrid',
        '00000000-0000-0000-0000-000000000032',
        'Seminar Keynote',
        'seminar-keynote',
        'UTC'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return categories for community 1 ordered by order field then name
select is(
    list_event_categories('00000000-0000-0000-0000-000000000001'::uuid)::jsonb,
    '[
        {
            "events_count": 2,
            "event_category_id": "00000000-0000-0000-0000-000000000012",
            "name": "Conference",
            "slug": "conference"
        },
        {
            "events_count": 1,
            "event_category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Workshop",
            "slug": "workshop"
        },
        {
            "events_count": 0,
            "event_category_id": "00000000-0000-0000-0000-000000000013",
            "name": "Meetup",
            "slug": "meetup"
        }
    ]'::jsonb,
    'Should return categories for community 1 ordered by order field then name'
);

-- Should return only categories for community 2
select is(
    list_event_categories('00000000-0000-0000-0000-000000000002'::uuid)::jsonb,
    '[
        {
            "events_count": 1,
            "event_category_id": "00000000-0000-0000-0000-000000000014",
            "name": "Seminar",
            "slug": "seminar"
        }
    ]'::jsonb,
    'Should return only categories for community 2'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
