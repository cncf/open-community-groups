-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000010'
\set communityID '00000000-0000-0000-0000-000000000001'
\set group2ID '00000000-0000-0000-0000-000000000003'
\set groupID '00000000-0000-0000-0000-000000000002'
\set sponsor1ID '00000000-0000-0000-0000-000000000061'
\set sponsor2ID '00000000-0000-0000-0000-000000000062'
\set sponsor3ID '00000000-0000-0000-0000-000000000063'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'Community 1', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Group Category (required by group)
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Tech', :'communityID');

-- Groups
insert into "group" (group_id, community_id, name, slug, group_category_id)
values
    (:'groupID', :'communityID', 'G1', 'g1', :'categoryID'),
    (:'group2ID', :'communityID', 'G2', 'g2', :'categoryID');

-- Group Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values
    (:'sponsor1ID', :'groupID', 'Alpha', 'https://e/s1.png', null),
    (:'sponsor2ID', :'groupID', 'Beta',  'https://e/s2.png',  'https://e/s2'),
    (:'sponsor3ID', :'group2ID', 'Gamma', 'https://e/s3.png', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return group sponsors sorted by name
select is(
    list_group_sponsors(
        :'groupID'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb,
        false
    )::jsonb,
    jsonb_build_object(
        'sponsors', '[
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000061", "logo_url": "https://e/s1.png", "name": "Alpha"},
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "logo_url": "https://e/s2.png", "name": "Beta", "website_url": "https://e/s2"}
        ]'::jsonb,
        'total', 2
    ),
    'Should return group sponsors sorted by name'
);

-- Should return paginated sponsors when limit and offset are provided
select is(
    list_group_sponsors(
        :'groupID'::uuid,
        '{"limit": 1, "offset": 1}'::jsonb,
        false
    )::jsonb,
    jsonb_build_object(
        'sponsors', '[
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "logo_url": "https://e/s2.png", "name": "Beta", "website_url": "https://e/s2"}
        ]'::jsonb,
        'total', 2
    ),
    'Should return paginated sponsors when limit and offset are provided'
);

-- Should return full list when full_list is true
select is(
    list_group_sponsors(
        :'groupID'::uuid,
        '{"limit": 1, "offset": 1}'::jsonb,
        true
    )::jsonb,
    jsonb_build_object(
        'sponsors', '[
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000061", "logo_url": "https://e/s1.png", "name": "Alpha"},
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "logo_url": "https://e/s2.png", "name": "Beta", "website_url": "https://e/s2"}
        ]'::jsonb,
        'total', 2
    ),
    'Should return full list when full_list is true'
);

-- Should return empty array for unknown group
select is(
    list_group_sponsors(
        '00000000-0000-0000-0000-000000000099'::uuid,
        '{"limit": 50, "offset": 0}'::jsonb,
        false
    )::jsonb,
    jsonb_build_object(
        'sponsors', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty array for unknown group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
