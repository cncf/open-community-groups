-- Tests group-level external-payments readiness.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e07e0000-0000-0000-0000-000000000001'
\set groupCategoryID 'e07e0000-0000-0000-0000-000000000002'
\set groupDisabledID 'e07e0000-0000-0000-0000-000000000003'
\set groupReadyID 'e07e0000-0000-0000-0000-000000000004'
\set groupUnlistedID 'e07e0000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Operator allowlist used by the group-readiness scenarios
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Community for group-readiness scenarios
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
    'external-group-ready-community',
    'External Group Ready Community',
    'Community for group readiness tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category for readiness scenarios
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Allowlisted group with the external-payments toggle enabled
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
    :'groupReadyID',
    'External Ready Group',
    'external-ready-group'
);

-- Allowlisted group with the external-payments toggle off
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
    false,
    :'groupCategoryID',
    :'groupDisabledID',
    'External Disabled Group',
    'external-disabled-group'
);

-- Enabled group whose country is outside the allowlist
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
    true,
    :'groupCategoryID',
    :'groupUnlistedID',
    'External Unlisted Group',
    'external-unlisted-group'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report ready when the toggle is on and the country is allowlisted
select is(
    is_group_external_payments_ready(:'groupReadyID'::uuid),
    true,
    'Should report ready when the toggle is on and the country is allowlisted'
);

-- Should report unready when the group toggle is off
select is(
    is_group_external_payments_ready(:'groupDisabledID'::uuid),
    false,
    'Should report unready when the group toggle is off'
);

-- Should report unready when the group country is not allowlisted
select is(
    is_group_external_payments_ready(:'groupUnlistedID'::uuid),
    false,
    'Should report unready when the group country is not allowlisted'
);

-- Should report unready for an unknown group
select is(
    is_group_external_payments_ready('00000000-0000-0000-0000-000000000000'::uuid),
    false,
    'Should report unready for an unknown group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
