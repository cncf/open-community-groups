-- Start transaction and plan tests
begin;
select plan(2);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'

-- Seed communities
insert into community (community_id, name, display_name, host, title, description, header_logo_url, theme)
values 
    (:'community1ID', 'test-community-1', 'Test Community 1', 'test1.localhost', 'Test Community 1 Title', 'A test community', 'https://example.com/logo.png', '{}'::jsonb),
    (:'community2ID', 'test-community-2', 'Test Community 2', 'test2.localhost', 'Test Community 2 Title', 'Another test community', 'https://example.com/logo2.png', '{}'::jsonb);

-- Seed event categories for community 1 (with order values)
insert into event_category (event_category_id, name, slug, community_id, "order")
values 
    ('00000000-0000-0000-0000-000000000011', 'Workshop', 'workshop', :'community1ID', 2),
    ('00000000-0000-0000-0000-000000000012', 'Conference', 'conference', :'community1ID', 1),
    ('00000000-0000-0000-0000-000000000013', 'Meetup', 'meetup', :'community1ID', null);

-- Seed event categories for community 2
insert into event_category (event_category_id, name, slug, community_id)
values 
    ('00000000-0000-0000-0000-000000000014', 'Seminar', 'seminar', :'community2ID');

-- Test: list_event_categories returns categories for specific community ordered correctly
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
    'list_event_categories should return categories for community 1 ordered by order field then name'
);

-- Test: list_event_categories returns only categories for the specified community
select is(
    list_event_categories('00000000-0000-0000-0000-000000000002'::uuid)::jsonb,
    '[
        {
            "event_category_id": "00000000-0000-0000-0000-000000000014",
            "name": "Seminar",
            "slug": "seminar"
        }
    ]'::jsonb,
    'list_event_categories should return only categories for community 2'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;