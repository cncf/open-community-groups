-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a240000-0000-0000-0000-000000000001'
\set groupCategoryID '3a240000-0000-0000-0000-000000000002'
\set groupID '3a240000-0000-0000-0000-000000000003'
\set missingGroupID '3a240000-0000-0000-0000-000000000004'
\set otherGroupID '3a240000-0000-0000-0000-000000000005'
\set sponsor1ID '3a240000-0000-0000-0000-000000000006'
\set sponsor2ID '3a240000-0000-0000-0000-000000000007'
\set sponsor3ID '3a240000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'test-alliance',
    'Test Alliance',
    'A test alliance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Tech');

-- Groups
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values
    (:'groupID', :'allianceID', :'groupCategoryID', 'Test Group', 'test-group'),
    (:'otherGroupID', :'allianceID', :'groupCategoryID', 'Other Group', 'other-group');

-- Group sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, featured, logo_url, website_url)
values (
    :'sponsor1ID',
    :'groupID',
    'Alpha',
    true,
    'https://example.com/s1.png',
    null
), (
    :'sponsor2ID',
    :'groupID',
    'Beta',
    false,
    'https://example.com/s2.png',
    'https://example.com/s2'
), (
    :'sponsor3ID',
    :'otherGroupID',
    'Gamma',
    false,
    'https://example.com/s3.png',
    null
);

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
        'sponsors', jsonb_build_array(
            jsonb_build_object(
                'featured', true,
                'group_sponsor_id', :'sponsor1ID'::uuid,
                'logo_url', 'https://example.com/s1.png',
                'name', 'Alpha'
            ),
            jsonb_build_object(
                'featured', false,
                'group_sponsor_id', :'sponsor2ID'::uuid,
                'logo_url', 'https://example.com/s2.png',
                'name', 'Beta',
                'website_url', 'https://example.com/s2'
            )
        ),
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
        'sponsors', jsonb_build_array(
            jsonb_build_object(
                'featured', false,
                'group_sponsor_id', :'sponsor2ID'::uuid,
                'logo_url', 'https://example.com/s2.png',
                'name', 'Beta',
                'website_url', 'https://example.com/s2'
            )
        ),
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
        'sponsors', jsonb_build_array(
            jsonb_build_object(
                'featured', true,
                'group_sponsor_id', :'sponsor1ID'::uuid,
                'logo_url', 'https://example.com/s1.png',
                'name', 'Alpha'
            ),
            jsonb_build_object(
                'featured', false,
                'group_sponsor_id', :'sponsor2ID'::uuid,
                'logo_url', 'https://example.com/s2.png',
                'name', 'Beta',
                'website_url', 'https://example.com/s2'
            )
        ),
        'total', 2
    ),
    'Should return full list when full_list is true'
);

-- Should return empty array for unknown group
select is(
    list_group_sponsors(
        :'missingGroupID'::uuid,
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
