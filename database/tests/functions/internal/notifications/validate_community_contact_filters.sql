-- Tests validating community contact filters.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '8a0b0000-0000-0000-0000-000000000001'
\set deletedGroupCategoryID '8a0b0000-0000-0000-0000-000000000002'
\set foreignCommunityID '8a0b0000-0000-0000-0000-000000000003'
\set foreignGroupCategoryID '8a0b0000-0000-0000-0000-000000000004'
\set foreignRegionID '8a0b0000-0000-0000-0000-000000000005'
\set groupCategoryID '8a0b0000-0000-0000-0000-000000000006'
\set regionID '8a0b0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose contact filters are validated
select fx_community(:'communityID');

-- Community owning the foreign filter values
select fx_community(:'foreignCommunityID');

-- Group category of the validated community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category of the foreign community
select fx_group_category(:'foreignGroupCategoryID', :'foreignCommunityID');

-- Region of the foreign community
insert into region (region_id, community_id, name)
values (:'foreignRegionID', :'foreignCommunityID', 'Foreign Region');

-- Region of the validated community
insert into region (region_id, community_id, name)
values (:'regionID', :'communityID', 'Local Region');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept empty filter lists
select lives_ok(
    format(
        $$select validate_community_contact_filters(
            %L::uuid,
            '{"group_category_ids": [], "regions": [], "roles": []}'::jsonb
        )$$,
        :'communityID'
    ),
    'Should accept empty filter lists'
);

-- Should accept filter values of the community
select lives_ok(
    format(
        $$select validate_community_contact_filters(
            %L::uuid,
            jsonb_build_object(
                'group_category_ids', jsonb_build_array(%L),
                'regions', jsonb_build_array(%L, 'none'),
                'roles', jsonb_build_array('admin', 'check-in-manager', 'events-manager', 'viewer')
            )
        )$$,
        :'communityID',
        :'groupCategoryID',
        :'regionID'
    ),
    'Should accept filter values of the community'
);

-- Should accept missing filter lists
select lives_ok(
    format(
        $$select validate_community_contact_filters(%L::uuid, '{}'::jsonb)$$,
        :'communityID'
    ),
    'Should accept missing filter lists'
);

-- Should reject deleted group categories
select throws_ok(
    format(
        $$select validate_community_contact_filters(
            %L::uuid,
            jsonb_build_object('group_category_ids', jsonb_build_array(%L))
        )$$,
        :'communityID',
        :'deletedGroupCategoryID'
    ),
    'OCG01',
    'group category not found',
    'Should reject deleted group categories'
);

-- Should reject group categories from another community
select throws_ok(
    format(
        $$select validate_community_contact_filters(
            %L::uuid,
            jsonb_build_object('group_category_ids', jsonb_build_array(%L))
        )$$,
        :'communityID',
        :'foreignGroupCategoryID'
    ),
    'OCG01',
    'group category not found',
    'Should reject group categories from another community'
);

-- Should reject malformed group category identifiers
select throws_ok(
    format(
        $$select validate_community_contact_filters(
            %L::uuid,
            '{"group_category_ids": ["not-a-uuid"]}'::jsonb
        )$$,
        :'communityID'
    ),
    'OCG01',
    'group category not found',
    'Should reject malformed group category identifiers'
);

-- Should reject malformed region values
select throws_ok(
    format(
        $$select validate_community_contact_filters(
            %L::uuid,
            '{"regions": ["nowhere"]}'::jsonb
        )$$,
        :'communityID'
    ),
    'OCG01',
    'invalid region',
    'Should reject malformed region values'
);

-- Should reject mixed valid and foreign filter values
select throws_ok(
    format(
        $$select validate_community_contact_filters(
            %L::uuid,
            jsonb_build_object(
                'group_category_ids', jsonb_build_array(%L),
                'regions', jsonb_build_array(%L, %L)
            )
        )$$,
        :'communityID',
        :'groupCategoryID',
        :'regionID',
        :'foreignRegionID'
    ),
    'OCG01',
    'region not found',
    'Should reject mixed valid and foreign filter values'
);

-- Should reject regions from another community
select throws_ok(
    format(
        $$select validate_community_contact_filters(
            %L::uuid,
            jsonb_build_object('regions', jsonb_build_array('none', %L))
        )$$,
        :'communityID',
        :'foreignRegionID'
    ),
    'OCG01',
    'region not found',
    'Should reject regions from another community'
);

-- Should reject unknown group roles
select throws_ok(
    format(
        $$select validate_community_contact_filters(
            %L::uuid,
            '{"roles": ["admin", "organizer"]}'::jsonb
        )$$,
        :'communityID'
    ),
    'OCG01',
    'group role not found',
    'Should reject unknown group roles'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
