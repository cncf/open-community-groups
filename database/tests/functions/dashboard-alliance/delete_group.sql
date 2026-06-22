-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '2c0a0000-0000-0000-0000-000000000001'
\set groupAlreadyDeletedID '2c0a0000-0000-0000-0000-000000000002'
\set groupCategoryID '2c0a0000-0000-0000-0000-000000000003'
\set groupID '2c0a0000-0000-0000-0000-000000000004'
\set groupWrongAllianceID '2c0a0000-0000-0000-0000-000000000005'
\set unknownAllianceID '2c0a0000-0000-0000-0000-000000000006'

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
    'delete-group-alliance',
    'Delete Group Alliance',
    'Alliance for delete group tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Active group
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

-- Already deleted group
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

-- Active group used to exercise the cross-alliance guard
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug
) values (
    :'groupWrongAllianceID',
    :'allianceID',
    :'groupCategoryID',
    'Cross Alliance Guard Group',
    'cross-alliance-guard-group'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should perform soft delete
select lives_ok(
    format(
        'select delete_group(null::uuid, %L::uuid, %L::uuid)',
        :'allianceID',
        :'groupID'
    ),
    'Should perform soft delete'
);

select is(
    (select deleted from "group" where group_id = :'groupID'::uuid),
    true,
    'Should set deleted to true'
);

select ok(
    (select deleted_at from "group" where group_id = :'groupID'::uuid) is not null,
    'Should set deleted_at timestamp'
);

-- Should perform soft delete (record still exists)
select ok(
    exists(select 1 from "group" where group_id = :'groupID'::uuid),
    'Should perform soft delete (record still exists)'
);

-- Should set active to false when deleting
select is(
    (select active from "group" where group_id = :'groupID'::uuid),
    false,
    'Should set active to false when deleting'
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
            'group_deleted',
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

-- Should throw error for already deleted group
select throws_ok(
    format(
        $$select delete_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'allianceID',
        :'groupAlreadyDeletedID'
    ),
    'group not found or inactive',
    'Should throw error when trying to delete already deleted group'
);

-- Should throw error for wrong alliance_id
select throws_ok(
    format(
        $$select delete_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'unknownAllianceID',
        :'groupWrongAllianceID'
    ),
    'group not found or inactive',
    'Should throw error when alliance_id does not match'
);

-- Should leave the group untouched when alliance_id does not match
select is(
    (select deleted from "group" where group_id = :'groupWrongAllianceID'::uuid),
    false,
    'Should leave the group untouched when alliance_id does not match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
