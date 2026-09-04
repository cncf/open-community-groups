-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '3a3e0000-0000-0000-0000-000000000001'
\set communityID '3a3e0000-0000-0000-0000-000000000002'
\set groupCategoryID '3a3e0000-0000-0000-0000-000000000003'
\set groupID '3a3e0000-0000-0000-0000-000000000004'
\set sponsorID '3a3e0000-0000-0000-0000-000000000005'
\set wrongGroupID '3a3e0000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'wrongGroupID', :'communityID', :'groupCategoryID');

-- Sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url, featured)
values (:'sponsorID', :'groupID', 'Iota', 'https://ex.com/iota.png', null, false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update the featured flag to true
select lives_ok(
    format(
        $$select update_group_sponsor_featured(%L::uuid, %L::uuid, %L::uuid, true)$$,
        :'actorUserID', :'groupID', :'sponsorID'
    ),
    'Should update the featured flag to true'
);
select results_eq(
    format(
        $$select featured from group_sponsor where group_sponsor_id = %L::uuid$$,
        :'sponsorID'
    ),
    $$values (true)$$,
    'Should persist the updated featured flag'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            community_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
        order by created_at asc
    $$,
    format(
        $$
        values (
            'group_sponsor_updated',
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'group_sponsor',
            %L::uuid
        )
        $$,
        :'actorUserID', :'communityID', :'groupID', :'sponsorID'
    ),
    'Should create the expected audit row'
);

-- Should update the featured flag back to false
select lives_ok(
    format(
        $$select update_group_sponsor_featured(%L::uuid, %L::uuid, %L::uuid, false)$$,
        :'actorUserID', :'groupID', :'sponsorID'
    ),
    'Should update the featured flag to false'
);
select results_eq(
    format(
        $$select featured from group_sponsor where group_sponsor_id = %L::uuid$$,
        :'sponsorID'
    ),
    $$values (false)$$,
    'Should persist the featured flag when disabling it'
);

-- Should create another audit row for the second update
select results_eq(
    $$select count(*) from audit_log$$,
    $$values (2::bigint)$$,
    'Should create an audit row for each featured flag update'
);

-- Should silently ignore updates for a sponsor outside the selected group
select lives_ok(
    format(
        $$select update_group_sponsor_featured(%L::uuid, %L::uuid, %L::uuid, true)$$,
        :'actorUserID', :'wrongGroupID', :'sponsorID'
    ),
    'Should accept featured updates for a sponsor outside the selected group without error'
);

select results_eq(
    format(
        $$select featured from group_sponsor where group_sponsor_id = %L::uuid$$,
        :'sponsorID'
    ),
    $$values (false)$$,
    'Should leave the featured flag unchanged when sponsor belongs to another group'
);

select results_eq(
    $$select count(*) from audit_log$$,
    $$values (2::bigint)$$,
    'Should not create an audit row when sponsor belongs to another group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
