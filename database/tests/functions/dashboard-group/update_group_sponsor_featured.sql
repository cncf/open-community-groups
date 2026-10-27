-- Tests updating the featured flag of group sponsors.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '3a3e0000-0000-0000-0000-000000000001'
\set communityID '3a3e0000-0000-0000-0000-000000000002'
\set groupCategoryID '3a3e0000-0000-0000-0000-000000000003'
\set groupID '3a3e0000-0000-0000-0000-000000000004'
\set sponsorFeaturedID '3a3e0000-0000-0000-0000-000000000005'
\set sponsorID '3a3e0000-0000-0000-0000-000000000006'
\set sponsorWrongGroupID '3a3e0000-0000-0000-0000-000000000007'
\set wrongGroupID '3a3e0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Actor updating the featured flags
select fx_user(:'actorUserID', jsonb_build_object('username', 'update-group-sponsor-featured-actor'));

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the sponsors
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group that does not own the sponsors
select fx_group(:'wrongGroupID', :'communityID', :'groupCategoryID');

-- Featured sponsor disabled by the unfeature scenario
insert into group_sponsor (featured, group_id, group_sponsor_id, logo_url, name, website_url)
values (true, :'groupID', :'sponsorFeaturedID', 'https://ex.com/eta.png', 'Eta', null);

-- Non-featured sponsor enabled by the feature scenario
insert into group_sponsor (featured, group_id, group_sponsor_id, logo_url, name, website_url)
values (false, :'groupID', :'sponsorID', 'https://ex.com/iota.png', 'Iota', null);

-- Non-featured sponsor targeted through a group that does not own it
insert into group_sponsor (featured, group_id, group_sponsor_id, logo_url, name, website_url)
values (false, :'groupID', :'sponsorWrongGroupID', 'https://ex.com/lambda.png', 'Lambda', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject featured updates for a sponsor outside the selected group
select throws_ok(
    format(
        $$select update_group_sponsor_featured(%L::uuid, %L::uuid, %L::uuid, true)$$,
        :'actorUserID', :'wrongGroupID', :'sponsorWrongGroupID'
    ),
    'OCG01',
    'sponsor not found',
    'Should reject featured updates for a sponsor outside the selected group'
);

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
    format(
        $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
        where resource_id = %L::uuid
        $$,
        :'sponsorID'
    ),
    format(
        $$
        values (
            'group_sponsor_updated',
            %L::uuid,
            'update-group-sponsor-featured-actor',
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

-- Should update the featured flag to false
select lives_ok(
    format(
        $$select update_group_sponsor_featured(%L::uuid, %L::uuid, %L::uuid, false)$$,
        :'actorUserID', :'groupID', :'sponsorFeaturedID'
    ),
    'Should update the featured flag to false'
);

select results_eq(
    format(
        $$select featured from group_sponsor where group_sponsor_id = %L::uuid$$,
        :'sponsorFeaturedID'
    ),
    $$values (false)$$,
    'Should persist the featured flag when disabling it'
);

select results_eq(
    format(
        $$
        select action, actor_user_id
        from audit_log
        where resource_id = %L::uuid
        $$,
        :'sponsorFeaturedID'
    ),
    format(
        $$ values ('group_sponsor_updated', %L::uuid) $$,
        :'actorUserID'
    ),
    'Should create an audit row when disabling the featured flag'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
