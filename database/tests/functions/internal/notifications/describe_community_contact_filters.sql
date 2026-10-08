-- Tests describing community contact filters with readable names.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alphaCategoryID '8a0d0000-0000-0000-0000-000000000002'
\set betaCategoryID '8a0d0000-0000-0000-0000-000000000003'
\set communityID '8a0d0000-0000-0000-0000-000000000001'
\set eastRegionID '8a0d0000-0000-0000-0000-000000000006'
\set unselectedCategoryID '8a0d0000-0000-0000-0000-000000000005'
\set unselectedRegionID '8a0d0000-0000-0000-0000-000000000008'
\set zetaCategoryID '8a0d0000-0000-0000-0000-000000000004'
\set zuluRegionID '8a0d0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose contact filters are described
select fx_community(:'communityID');

-- Unordered group category sorted by name
select fx_group_category(:'alphaCategoryID', :'communityID', jsonb_build_object('name', 'Alpha'));

-- Second unordered group category sorted by name
select fx_group_category(:'betaCategoryID', :'communityID', jsonb_build_object('name', 'Beta'));

-- Group category left out of the selected filters
select fx_group_category(:'unselectedCategoryID', :'communityID', jsonb_build_object('name', 'Unselected'));

-- Ordered group category sorted before unordered ones
select fx_group_category(
    :'zetaCategoryID',
    :'communityID',
    jsonb_build_object('name', 'Zeta', 'order', 1)
);

-- Unordered region sorted by name
insert into region (region_id, community_id, name)
values (:'eastRegionID', :'communityID', 'East');

-- Region left out of the selected filters
insert into region (region_id, community_id, name)
values (:'unselectedRegionID', :'communityID', 'West');

-- Ordered region sorted before unordered ones
insert into region (region_id, community_id, name, "order")
values (:'zuluRegionID', :'communityID', 'Zulu', 1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should describe empty filter lists as All
select is(
    describe_community_contact_filters(
        :'communityID'::uuid,
        '{"group_category_ids": [], "regions": [], "roles": []}'::jsonb
    ),
    '{"group_categories": "All", "regions": "All", "roles": "All"}'::jsonb,
    'Should describe empty filter lists as All'
);

-- Should describe missing filter lists as All
select is(
    describe_community_contact_filters(:'communityID'::uuid, '{}'::jsonb),
    '{"group_categories": "All", "regions": "All", "roles": "All"}'::jsonb,
    'Should describe missing filter lists as All'
);

-- Should describe selected filter values with ordered names
select is(
    describe_community_contact_filters(
        :'communityID'::uuid,
        jsonb_build_object(
            'group_category_ids', jsonb_build_array(
                :'betaCategoryID',
                :'alphaCategoryID',
                :'zetaCategoryID',
                :'betaCategoryID'
            ),
            'regions', jsonb_build_array('none', :'eastRegionID', :'zuluRegionID'),
            'roles', jsonb_build_array('viewer', 'check-in-manager', 'admin', 'events-manager')
        )
    ),
    '{
        "group_categories": ["Zeta", "Alpha", "Beta"],
        "regions": ["Zulu", "East", "No region"],
        "roles": ["Admin", "Events Manager", "Check-In Manager", "Viewer"]
    }'::jsonb,
    'Should describe selected filter values with ordered names'
);

-- Should describe the no region option alone
select is(
    describe_community_contact_filters(
        :'communityID'::uuid,
        '{"regions": ["none"], "roles": ["viewer"]}'::jsonb
    ),
    '{"group_categories": "All", "regions": ["No region"], "roles": ["Viewer"]}'::jsonb,
    'Should describe the no region option alone'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
