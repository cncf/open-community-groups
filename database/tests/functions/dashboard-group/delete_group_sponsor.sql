-- Tests deleting group sponsors.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '3a0c0000-0000-0000-0000-000000000008'
\set communityID '3a0c0000-0000-0000-0000-000000000001'
\set eventCategoryID '3a0c0000-0000-0000-0000-000000000002'
\set eventID '3a0c0000-0000-0000-0000-000000000003'
\set groupCategoryID '3a0c0000-0000-0000-0000-000000000004'
\set groupID '3a0c0000-0000-0000-0000-000000000005'
\set otherGroupID '3a0c0000-0000-0000-0000-000000000007'
\set sponsorID '3a0c0000-0000-0000-0000-000000000006'
\set sponsorUnreferencedID '3a0c0000-0000-0000-0000-000000000009'
\set sponsorWrongGroupID '3a0c0000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group that does not own the sponsors
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Actor deleting the sponsors
select fx_user(:'actorUserID', jsonb_build_object('username', 'delete-group-sponsor-actor'));

-- Event referencing the sponsor
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Sponsor referenced by an event
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values (:'sponsorID', :'groupID', 'Kappa', 'https://ex.com/kappa.png', null);

-- Unreferenced sponsor deleted by its owning group
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values (:'sponsorUnreferencedID', :'groupID', 'Lambda', 'https://ex.com/lambda.png', null);

-- Unreferenced sponsor targeted through a group that does not own it
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values (:'sponsorWrongGroupID', :'groupID', 'Mu', 'https://ex.com/mu.png', null);

-- Event reference to the sponsor
insert into event_sponsor (event_id, group_sponsor_id, level)
values (:'eventID', :'sponsorID', 'Gold');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should delete an unreferenced sponsor
select lives_ok(
    format(
        $$select delete_group_sponsor(%L::uuid, %L::uuid, %L::uuid)$$,
        :'actorUserID', :'groupID', :'sponsorUnreferencedID'
    ),
    'Should delete an unreferenced sponsor'
);

-- Should remove the unreferenced sponsor
select is(
    (select count(*) from group_sponsor where group_sponsor_id = :'sponsorUnreferencedID'::uuid),
    0::bigint,
    'Should remove the unreferenced sponsor'
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
        :'sponsorUnreferencedID'
    ),
    format(
        $$
        values (
            'group_sponsor_deleted',
            %L::uuid,
            'delete-group-sponsor-actor',
            %L::uuid,
            %L::uuid,
            'group_sponsor',
            %L::uuid
        )
        $$,
        :'actorUserID', :'communityID', :'groupID', :'sponsorUnreferencedID'
    ),
    'Should create the expected audit row'
);

-- Should fail when sponsor is referenced by event
select throws_ok(
    format(
        $$select delete_group_sponsor(%L::uuid, %L::uuid, %L::uuid)$$,
        :'actorUserID', :'groupID', :'sponsorID'
    ),
    'OCG01',
    'sponsor is used by one or more events',
    'Should fail when sponsor is referenced by event'
);

-- Should ignore a sponsor that belongs to another group
select lives_ok(
    format(
        $$select delete_group_sponsor(%L::uuid, %L::uuid, %L::uuid)$$,
        :'actorUserID', :'otherGroupID', :'sponsorWrongGroupID'
    ),
    'Should ignore a sponsor that belongs to another group'
);

-- Should keep the sponsor that belongs to another group
select is(
    (select count(*) from group_sponsor where group_sponsor_id = :'sponsorWrongGroupID'::uuid),
    1::bigint,
    'Should keep the sponsor that belongs to another group'
);

-- Should not audit a sponsor deletion that matched no row
select is(
    (
        select count(*)
        from audit_log
        where action = 'group_sponsor_deleted'
        and resource_id = :'sponsorWrongGroupID'::uuid
    ),
    0::bigint,
    'Should not audit a sponsor deletion that matched no row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
