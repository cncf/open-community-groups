-- Tests updating dashboard community regions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '2c180000-0000-0000-0000-000000000006'
\set communityID '2c180000-0000-0000-0000-000000000001'
\set foreignRegionID '2c180000-0000-0000-0000-000000000004'
\set otherCommunityID '2c180000-0000-0000-0000-000000000005'
\set region1ID '2c180000-0000-0000-0000-000000000002'
\set region2ID '2c180000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community
select fx_community(:'communityID');

-- Updated region and second region whose name the duplicate scenario reuses
insert into region (
    region_id,
    community_id,
    name
) values
    (:'region1ID', :'communityID', 'North America'),
    (:'region2ID', :'communityID', 'Europe');

-- Other community with its own region
select fx_community(:'otherCommunityID');
insert into region (region_id, community_id, name)
values (:'foreignRegionID', :'otherCommunityID', 'Asia');

-- Actor recorded in the audit row
select fx_user(:'actorUserID', jsonb_build_object('username', 'update-region-audit-actor'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update region name and generated normalized name
select lives_ok(
    format(
        $$ select update_region(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Latin America')
    ) $$,
        :'actorUserID',
        :'communityID',
        :'region1ID'
    ),
    'Should update region name'
);
select results_eq(
    format(
        $$
    select
        r.name,
        r.normalized_name
    from region r
    where r.region_id = %L::uuid
        $$,
        :'region1ID'
    ),
    $$ values ('Latin America'::text, 'latin-america'::text) $$,
    'Should persist updated region values'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'region_updated',
            %L::uuid,
            'update-region-audit-actor',
            %L::uuid,
            'region',
            %L::uuid
        )
        $$,
        :'actorUserID',
        :'communityID',
        :'region1ID'
    ),
    'Should create the expected audit row'
);

-- Should reject duplicate normalized names in same community
select throws_ok(
    format(
        $$ select update_region(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Europe')
    ) $$,
        :'communityID',
        :'region1ID'
    ),
    'OCG01',
    'region already exists',
    'Should reject duplicate region names'
);

-- Should fail when target region belongs to another community
select throws_ok(
    format(
        $$ select update_region(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'APAC')
    ) $$,
        :'communityID',
        :'foreignRegionID'
    ),
    'OCG01',
    'region not found',
    'Should fail when updating a region from another community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
