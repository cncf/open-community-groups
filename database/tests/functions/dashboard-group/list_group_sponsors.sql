-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set group1ID '00000000-0000-0000-0000-000000000002'
\set group2ID '00000000-0000-0000-0000-000000000003'
\set sponsor1ID '00000000-0000-0000-0000-000000000061'
\set sponsor2ID '00000000-0000-0000-0000-000000000062'
\set sponsor3ID '00000000-0000-0000-0000-000000000063'

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
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group Category (required by group)
insert into group_category (group_category_id, name, community_id)
values ('00000000-0000-0000-0000-000000000010', 'Technology', :'communityID');

-- Groups
insert into "group" (group_id, community_id, name, slug, group_category_id)
values
    (:'group1ID', :'communityID', 'Group One', 'group-one', '00000000-0000-0000-0000-000000000010'),
    (:'group2ID', :'communityID', 'Group Two', 'group-two', '00000000-0000-0000-0000-000000000010');

-- Group Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values
    (:'sponsor1ID', :'group1ID', 'Alpha', 'https://ex.com/alpha.png', null),
    (:'sponsor2ID', :'group1ID', 'Beta',  'https://ex.com/beta.png',  'https://beta.io'),
    (:'sponsor3ID', :'group2ID', 'Gamma', 'https://ex.com/gamma.png', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return group sponsors sorted by name
select is(
    list_group_sponsors(:'group1ID'::uuid, '{}'::jsonb)::jsonb,
    jsonb_build_object(
        'sponsors', '[
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000061", "logo_url": "https://ex.com/alpha.png", "name": "Alpha"},
            {"group_sponsor_id": "00000000-0000-0000-0000-000000000062", "logo_url": "https://ex.com/beta.png", "name": "Beta", "website_url": "https://beta.io"}
        ]'::jsonb,
        'total', 2
    ),
    'Should return group sponsors sorted by name'
);

-- Should return empty array for unknown group
select is(
    list_group_sponsors('00000000-0000-0000-0000-000000000099'::uuid, '{}'::jsonb)::jsonb,
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
