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
insert into community (community_id, name, display_name, host, title, description, header_logo_url, theme)
values 
    (:'community1ID', 'cloud-native-seattle', 'Cloud Native Seattle', 'seattle.cloudnative.org', 'Cloud Native Seattle Community', 'A vibrant community for cloud native technologies and practices in Seattle', 'https://example.com/logo.png', '{}'::jsonb),
    (:'community2ID', 'devops-vancouver', 'DevOps Vancouver', 'vancouver.devops.org', 'DevOps Vancouver Community', 'Building DevOps expertise and community in Vancouver', 'https://example.com/logo2.png', '{}'::jsonb);

-- Event Category
insert into event_category (event_category_id, name, slug, community_id, "order")
values 
    ('00000000-0000-0000-0000-000000000011', 'Workshop', 'workshop', :'community1ID', 2),
    ('00000000-0000-0000-0000-000000000012', 'Conference', 'conference', :'community1ID', 1),
    ('00000000-0000-0000-0000-000000000013', 'Meetup', 'meetup', :'community1ID', null);

-- Event Category (other community)
insert into event_category (event_category_id, name, slug, community_id)
values 
    ('00000000-0000-0000-0000-000000000014', 'Seminar', 'seminar', :'community2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return categories for community 1 ordered by order field then name
select is(
    list_event_categories('00000000-0000-0000-0000-000000000001'::uuid)::jsonb,
    '[
        {
            "event_category_id": "00000000-0000-0000-0000-000000000012",
            "name": "Conference",
            "slug": "conference"
        },
        {
            "event_category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Workshop",
            "slug": "workshop"
        },
        {
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
