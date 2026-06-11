-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '2c170000-0000-0000-0000-000000000001'
\set groupCategory1ID '2c170000-0000-0000-0000-000000000002'
\set groupCategory2ID '2c170000-0000-0000-0000-000000000003'
\set unknownGroupCategoryID '2c170000-0000-0000-0000-000000000004'

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
    'Community for group category update tests',
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
    (:'groupCategory1ID', :'communityID', 'Meetup'),
    (:'groupCategory2ID', :'communityID', 'Conference');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update category name and generated normalized name
select lives_ok(
    format(
        $$ select update_group_category(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Lightning Talks')
    ) $$,
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
            null::uuid,
            null::text,
            %L::uuid,
            'group_category',
            %L::uuid
        )
        $$,
        :'communityID',
        :'groupCategory1ID'
    ),
    'Should create the expected audit row'
);

-- Should reject duplicate normalized names in same community
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
    'group category already exists',
    'Should reject duplicate group category names'
);

-- Should fail when target category does not exist
select throws_ok(
    format(
        $$ select update_group_category(
        null::uuid,
        %L::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Workshops')
    ) $$,
        :'communityID',
        :'unknownGroupCategoryID'
    ),
    'group category not found',
    'Should fail when updating a non-existing group category'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
