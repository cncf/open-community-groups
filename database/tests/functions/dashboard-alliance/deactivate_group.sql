-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '2c070000-0000-0000-0000-000000000001'
\set groupAlreadyDeletedID '2c070000-0000-0000-0000-000000000002'
\set groupAlreadyInactiveID '2c070000-0000-0000-0000-000000000003'
\set groupCategoryID '2c070000-0000-0000-0000-000000000004'
\set groupID '2c070000-0000-0000-0000-000000000005'
\set unknownAllianceID '2c070000-0000-0000-0000-000000000006'
\set unknownGroupID '2c070000-0000-0000-0000-000000000007'

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
    'deactivate-group-alliance',
    'Deactivate Group Alliance',
    'Alliance for deactivate group tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug
) values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Active Group',
    'active-group'
);

-- Group (deleted)
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values (
    :'groupAlreadyDeletedID',
    :'allianceID',
    :'groupCategoryID',
    'Deleted Group',
    'deleted-group',
    false,
    true
);

-- Group (inactive)
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values (
    :'groupAlreadyInactiveID',
    :'allianceID',
    :'groupCategoryID',
    'Inactive Group',
    'inactive-group',
    false,
    false
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should set active to false
select lives_ok(
    format(
        'select deactivate_group(null::uuid, %L::uuid, %L::uuid)',
        :'allianceID',
        :'groupID'
    ),
    'Should execute deactivate_group successfully'
);

-- Should set active to false
select is(
    (select active from "group" where group_id = :'groupID'::uuid),
    false,
    'Should set active flag to false'
);

-- Should not set deleted flag
select is(
    (select deleted from "group" where group_id = :'groupID'::uuid),
    false,
    'Should not set deleted flag'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            alliance_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'group_deactivated',
            null::uuid,
            null::text,
            %L::uuid,
            %L::uuid,
            'group',
            %L::uuid
        )
        $$,
        :'allianceID',
        :'groupID',
        :'groupID'
    ),
    'Should create the expected audit row'
);

-- Should be idempotent for already inactive groups
select lives_ok(
    format(
        $$select deactivate_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'allianceID',
        :'groupAlreadyInactiveID'
    ),
    'Should be idempotent for already inactive groups'
);

-- Should throw error for already deleted group
select throws_ok(
    format(
        $$select deactivate_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'allianceID',
        :'groupAlreadyDeletedID'
    ),
    'group not found or inactive',
    'Should throw error when trying to deactivate already deleted group'
);

-- Should throw error for wrong alliance_id
select throws_ok(
    format(
        $$select deactivate_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'unknownAllianceID',
        :'groupID'
    ),
    'group not found or inactive',
    'Should throw error when alliance_id does not match'
);

-- Should throw error for non-existent group
select throws_ok(
    format(
        $$select deactivate_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'allianceID',
        :'unknownGroupID'
    ),
    'group not found or inactive',
    'Should throw error for non-existent group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
