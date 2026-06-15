-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c0b0000-0000-0000-0000-000000000001'
\set groupID '2c0b0000-0000-0000-0000-000000000002'
\set inUseGroupCategoryID '2c0b0000-0000-0000-0000-000000000003'
\set unknownGroupCategoryID '2c0b0000-0000-0000-0000-000000000004'
\set unusedGroupCategoryID '2c0b0000-0000-0000-0000-000000000005'

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
    'cncf-seattle',
    'CNCF Seattle',
    'Community for group category delete tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group categories
insert into group_category (
    group_category_id,
    community_id,
    name
) values
    (:'inUseGroupCategoryID', :'communityID', 'Platform'),
    (:'unusedGroupCategoryID', :'communityID', 'Security');

-- Group using the first category
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug
) values (
    :'groupID',
    :'communityID',
    :'inUseGroupCategoryID',
    'Seattle Platform',
    'seattle-platform'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block deleting category that is still referenced by groups
select throws_ok(
    format(
        $$ select delete_group_category(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'inUseGroupCategoryID'
    ),
    'cannot delete group category in use by groups',
    'Should block deleting group category referenced by groups'
);

-- Should delete category with no group references
select lives_ok(
    format(
        $$ select delete_group_category(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'unusedGroupCategoryID'
    ),
    'Should delete an unused group category'
);
select results_eq(
    format(
        $$
    select count(*)::bigint
    from group_category gc
    where gc.group_category_id = %L::uuid
        $$,
        :'unusedGroupCategoryID'
    ),
    $$ values (0::bigint) $$,
    'Unused group category should be deleted'
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
            'group_category_deleted',
            null::uuid,
            null::text,
            %L::uuid,
            '{"name": "Security"}'::jsonb,
            'group_category',
            %L::uuid
        )
        $$,
        :'communityID',
        :'unusedGroupCategoryID'
    ),
    'Should create the expected audit row'
);

-- Should fail when target category does not exist
select throws_ok(
    format(
        $$ select delete_group_category(
        null::uuid,
        %L::uuid,
        %L::uuid
    ) $$,
        :'communityID',
        :'unknownGroupCategoryID'
    ),
    'group category not found',
    'Should fail when deleting a non-existing group category'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
