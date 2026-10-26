-- Tests deleting dashboard community regions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '2c0c0000-0000-0000-0000-000000000008'
\set communityID '2c0c0000-0000-0000-0000-000000000001'
\set foreignRegionID '2c0c0000-0000-0000-0000-000000000005'
\set groupCategoryID '2c0c0000-0000-0000-0000-000000000002'
\set groupID '2c0c0000-0000-0000-0000-000000000003'
\set inUseRegionID '2c0c0000-0000-0000-0000-000000000004'
\set otherCommunityID '2c0c0000-0000-0000-0000-000000000007'
\set unusedRegionID '2c0c0000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and group category
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Region in use by a group and unused region deleted by the success scenario
insert into region (
    region_id,
    community_id,
    name
) values
    (:'inUseRegionID', :'communityID', 'North America'),
    (:'unusedRegionID', :'communityID', 'Europe');

-- Group using the first region
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('region_id', :'inUseRegionID'));

-- Other community with its own region
select fx_community(:'otherCommunityID');
insert into region (region_id, community_id, name)
values (:'foreignRegionID', :'otherCommunityID', 'Asia');

-- Actor recorded in the audit row
select fx_user(:'actorUserID', jsonb_build_object('username', 'delete-region-audit-actor'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block deleting region that is still referenced by groups
select throws_ok(
    format(
        $$ select delete_region(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'inUseRegionID'
    ),
    'OCG01',
    'cannot delete region in use by groups',
    'Should block deleting region referenced by groups'
);

-- Should delete region with no group references
select lives_ok(
    format(
        $$ select delete_region(
        %L::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'actorUserID',
        :'communityID',
        :'unusedRegionID'
    ),
    'Should delete an unused region'
);
select results_eq(
    format(
        $$
    select count(*)::bigint
    from region r
    where r.region_id = %L::uuid
        $$,
        :'unusedRegionID'
    ),
    $$ values (0::bigint) $$,
    'Unused region should be deleted'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            details,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'region_deleted',
            %L::uuid,
            'delete-region-audit-actor',
            %L::uuid,
            '{"name": "Europe"}'::jsonb,
            'region',
            %L::uuid
        )
        $$,
        :'actorUserID',
        :'communityID',
        :'unusedRegionID'
    ),
    'Should create the expected audit row'
);

-- Should fail when target region belongs to another community
select throws_ok(
    format(
        $$ select delete_region(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'foreignRegionID'
    ),
    'OCG01',
    'region not found',
    'Should fail when deleting a region from another community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
