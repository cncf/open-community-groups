-- Tests updating dashboard community group categories.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '2c170000-0000-0000-0000-000000000006'
\set communityID '2c170000-0000-0000-0000-000000000001'
\set foreignGroupCategoryID '2c170000-0000-0000-0000-000000000004'
\set groupCategory1ID '2c170000-0000-0000-0000-000000000002'
\set groupCategory2ID '2c170000-0000-0000-0000-000000000003'
\set otherCommunityID '2c170000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the taxonomy under test
select fx_community(:'communityID');

-- Other community owning the foreign group category
select fx_community(:'otherCommunityID');

-- Actor recorded in the audit row
select fx_user(:'actorUserID', jsonb_build_object('username', 'update-group-category-audit-actor'));

-- Group category owned by the other community
select fx_group_category(:'foreignGroupCategoryID', :'otherCommunityID');

-- Group category updated by the scenarios
select fx_group_category(:'groupCategory1ID', :'communityID');

-- Second group category whose name the duplicate scenario reuses
select fx_group_category(:'groupCategory2ID', :'communityID', jsonb_build_object('name', 'Conference'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should fail when updating a group category from another community
select throws_ok(
    format(
        $$ select update_group_category(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Workshops')
    ) $$,
        :'communityID',
        :'foreignGroupCategoryID'
    ),
    'OCG01',
    'group category not found',
    'Should fail when updating a group category from another community'
);

-- Should reject duplicate group category names
select throws_ok(
    format(
        $$ select update_group_category(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Conference')
    ) $$,
        :'communityID',
        :'groupCategory1ID'
    ),
    'OCG01',
    'group category already exists',
    'Should reject duplicate group category names'
);

-- Should update group category name
select lives_ok(
    format(
        $$ select update_group_category(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Lightning Talks')
    ) $$,
        :'actorUserID',
        :'communityID',
        :'groupCategory1ID'
    ),
    'Should update group category name'
);
select results_eq(
    format(
        $$
    select
        gc.name,
        gc.normalized_name
    from group_category gc
    where gc.group_category_id = %L::uuid
        $$,
        :'groupCategory1ID'
    ),
    $$ values ('Lightning Talks'::text, 'lightning-talks'::text) $$,
    'Should persist updated group category values'
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
            'group_category_updated',
            %L::uuid,
            'update-group-category-audit-actor',
            %L::uuid,
            'group_category',
            %L::uuid
        )
        $$,
        :'actorUserID',
        :'communityID',
        :'groupCategory1ID'
    ),
    'Should create the expected audit row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
