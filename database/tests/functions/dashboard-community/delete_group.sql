-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c0a0000-0000-0000-0000-000000000001'
\set childGroupID '2c0a0000-0000-0000-0000-000000000007'
\set groupAlreadyDeletedID '2c0a0000-0000-0000-0000-000000000002'
\set groupCategoryID '2c0a0000-0000-0000-0000-000000000003'
\set groupID '2c0a0000-0000-0000-0000-000000000004'
\set groupWrongCommunityID '2c0a0000-0000-0000-0000-000000000005'
\set linkedGroupID '2c0a0000-0000-0000-0000-000000000008'
\set unknownCommunityID '2c0a0000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'delete-group-community',
    'Delete Group Community',
    'Community for delete group tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Active group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Active Group',
    'active-group'
);

-- Child group linked to the active group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    parent_group_id
) values (
    :'childGroupID',
    :'communityID',
    :'groupCategoryID',
    'Child Group',
    'child-group',
    :'groupID'
);

-- Already deleted group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values (
    :'groupAlreadyDeletedID',
    :'communityID',
    :'groupCategoryID',
    'Deleted Group',
    'deleted-group',
    false,
    true
);

-- Active group used to exercise the cross-community guard
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug
) values (
    :'groupWrongCommunityID',
    :'communityID',
    :'groupCategoryID',
    'Cross Community Guard Group',
    'cross-community-guard-group'
);

-- Group with its own parent link
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    parent_group_id
) values (
    :'linkedGroupID',
    :'communityID',
    :'groupCategoryID',
    'Linked Group',
    'linked-group',
    :'groupWrongCommunityID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should perform soft delete
select lives_ok(
    format(
        'select delete_group(null::uuid, %L::uuid, %L::uuid)',
        :'communityID',
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

-- Should clear child links for deleted parent group
select is(
    (select parent_group_id from "group" where group_id = :'childGroupID'::uuid),
    null::uuid,
    'Should clear child links for deleted parent group'
);

-- Should clear the deleted group's own parent link
select lives_ok(
    format(
        'select delete_group(null::uuid, %L::uuid, %L::uuid)',
        :'communityID',
        :'linkedGroupID'
    ),
    'Should delete a group that has a parent link'
);

select is(
    (select parent_group_id from "group" where group_id = :'linkedGroupID'::uuid),
    null::uuid,
    'Should clear the deleted group own parent link'
);

-- Should create the expected audit row
select results_eq(
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
    $$,
    format(
        $$
        values
            (
                'group_deleted',
                null::uuid,
                null::text,
                %L::uuid,
                %L::uuid,
                'group',
                %L::uuid
            ),
            (
                'group_deleted',
                null::uuid,
                null::text,
                %L::uuid,
                %L::uuid,
                'group',
                %L::uuid
            )
        $$,
        :'communityID',
        :'groupID',
        :'groupID',
        :'communityID',
        :'linkedGroupID',
        :'linkedGroupID'
    ),
    'Should create the expected audit row'
);

-- Should throw error for already deleted group
select throws_ok(
    format(
        $$select delete_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'communityID',
        :'groupAlreadyDeletedID'
    ),
    'group not found or inactive',
    'Should throw error when trying to delete already deleted group'
);

-- Should throw error for wrong community_id
select throws_ok(
    format(
        $$select delete_group(null::uuid, %L::uuid, %L::uuid)$$,
        :'unknownCommunityID',
        :'groupWrongCommunityID'
    ),
    'group not found or inactive',
    'Should throw error when community_id does not match'
);

-- Should leave the group untouched when community_id does not match
select is(
    (select deleted from "group" where group_id = :'groupWrongCommunityID'::uuid),
    false,
    'Should leave the group untouched when community_id does not match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
