-- Tests group-level external-payments settings context.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e07c0000-0000-0000-0000-000000000001'
\set groupCategoryID 'e07c0000-0000-0000-0000-000000000002'
\set groupEligibleID 'e07c0000-0000-0000-0000-000000000003'
\set groupIneligibleID 'e07c0000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Operator allowlist used by the eligible-group scenario
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Community for settings-context scenarios
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
    'external-context-community',
    'External Context Community',
    'Community for external context tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category for settings-context scenarios
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Allowlisted group with the toggle enabled
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
    :'groupEligibleID',
    'Eligible External Group',
    'eligible-external-group'
);

-- Group whose country is not allowlisted
insert into "group" (
    country_code,
    community_id,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    'US',
    :'communityID',
    false,
    :'groupCategoryID',
    :'groupIneligibleID',
    'Ineligible External Group',
    'ineligible-external-group'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return eligibility, toggle, and window limits for an allowlisted group
select is(
    get_group_external_payments_context(
        :'communityID'::uuid,
        :'groupEligibleID'::uuid
    ),
    jsonb_build_object(
        'configured', true,
        'country_code', 'KR',
        'default_payment_window_hours', 72,
        'eligible', true,
        'enabled', true,
        'max_payment_window_hours', 336
    ),
    'Should return eligibility, toggle, and window limits for an allowlisted group'
);

-- Should return ineligible context for a group outside the allowlist
select is(
    get_group_external_payments_context(
        :'communityID'::uuid,
        :'groupIneligibleID'::uuid
    ),
    jsonb_build_object(
        'configured', true,
        'country_code', 'US',
        'default_payment_window_hours', 72,
        'eligible', false,
        'enabled', false,
        'max_payment_window_hours', 336
    ),
    'Should return ineligible context for a group outside the allowlist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
