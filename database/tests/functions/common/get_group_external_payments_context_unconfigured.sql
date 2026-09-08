-- Tests group-level external-payments settings context without operator config.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e07d0000-0000-0000-0000-000000000001'
\set groupCategoryID 'e07d0000-0000-0000-0000-000000000002'
\set groupID 'e07d0000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for the unconfigured settings-context scenario
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
    'unconfigured-context-community',
    'Unconfigured Context Community',
    'Community for unconfigured external context tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category for the unconfigured settings-context scenario
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group whose operator config row is absent
insert into "group" (
    country_code,
    community_id,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    'KR',
    :'communityID',
    true,
    :'groupCategoryID',
    :'groupID',
    'Unconfigured External Group',
    'unconfigured-external-group'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report the operator config as absent when no row is synced
select is(
    get_group_external_payments_context(
        :'communityID'::uuid,
        :'groupID'::uuid
    ),
    jsonb_build_object(
        'configured', false,
        'country_code', 'KR',
        'eligible', false,
        'enabled', true
    ),
    'Should report the operator config as absent when no row is synced'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
