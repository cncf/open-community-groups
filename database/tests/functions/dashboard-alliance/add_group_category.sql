-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '2c050000-0000-0000-0000-000000000001'

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
    'cncf-seattle',
    'CNCF Seattle',
    'Alliance for group category tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create a new group category and auto-generate normalized name
select lives_ok(
    format(
        $$ select add_group_category(
        null::uuid,
        %L::uuid,
        jsonb_build_object('name', 'Platform Engineering')
    ) $$,
        :'allianceID'
    ),
    'Should create a group category with generated normalized name'
);
select results_eq(
    format(
        $$
    select
        gc.name,
        gc.normalized_name
    from group_category gc
    where gc.alliance_id = %L::uuid
        $$,
        :'allianceID'
    ),
    $$ values ('Platform Engineering'::text, 'platform-engineering'::text) $$,
    'Should store category name and generated normalized name'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            alliance_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        select
            'group_category_added',
            null::uuid,
            null::text,
            %L::uuid,
            'group_category',
            group_category_id
        from group_category
        where alliance_id = %L::uuid
        $$,
        :'allianceID',
        :'allianceID'
    ),
    'Should create the expected audit row'
);

-- Should not allow duplicate group category normalized name in same alliance
select throws_ok(
    format(
        $$ select add_group_category(
        null::uuid,
        %L::uuid,
        jsonb_build_object('name', 'platform engineering')
    ) $$,
        :'allianceID'
    ),
    'group category already exists',
    'Should reject duplicate group category names'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
