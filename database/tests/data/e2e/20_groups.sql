-- E2E seed: groups.
-- Depends on: 10_catalog.sql (communities, categories, regions).

-- ============================================================================
-- GROUPS
-- ============================================================================

-- Primary community groups used across the main e2e scenarios
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description,
    region_id,
    parent_group_id,
    active
) values (
    '44444444-4444-4444-4444-444444444441',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'Platform Ops Meetup',
    'test-group-alpha',
    'Primary meetup used for end-to-end dashboard and site coverage.',
    '22222222-2222-2222-2222-222222222301',
    null,
    true
), (
    '44444444-4444-4444-4444-444444444442',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'Inactive Local Chapter',
    'test-group-beta',
    null,
    '22222222-2222-2222-2222-222222222301',
    '44444444-4444-4444-4444-444444444441',
    true
), (
    '44444444-4444-4444-4444-444444444443',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'Observability Guild',
    'test-group-gamma',
    null,
    null,
    null,
    true
), (
    '44444444-4444-4444-4444-444444444447',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'Empty Coverage Group',
    'empty-coverage-group',
    'Dedicated group for empty dashboard states.',
    null,
    null,
    false
), (
    '44444444-4444-4444-4444-444444444448',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222221',
    'External Payments Lab',
    'external-payments-lab',
    'Dedicated group for external payment end-to-end coverage.',
    '22222222-2222-2222-2222-222222222301',
    null,
    true
);

-- Secondary community groups used for cross-community coverage
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    description,
    slug,
    active
) values (
    '44444444-4444-4444-4444-444444444444',
    '11111111-1111-1111-1111-111111111112',
    '22222222-2222-2222-2222-222222222222',
    'E2E Second Group Delta',
    'Secondary community group used for end-to-end dashboard coverage.',
    'second-group-delta',
    true
), (
    '44444444-4444-4444-4444-444444444445',
    '11111111-1111-1111-1111-111111111112',
    '22222222-2222-2222-2222-222222222222',
    'E2E Second Group Epsilon',
    null,
    'second-group-epsilon',
    true
), (
    '44444444-4444-4444-4444-444444444446',
    '11111111-1111-1111-1111-111111111112',
    '22222222-2222-2222-2222-222222222222',
    'E2E Second Group Zeta',
    null,
    'second-group-zeta',
    true
);

-- Enable payment-ready coverage on the primary group without changing the
-- current payments-disabled e2e server profile.
update "group"
set payment_recipient = '{"provider":"stripe","recipient_id":"acct_e2e_alpha","seller_display_name":"E2E Alpha Fiscal Sponsor"}'::jsonb
where group_id = '44444444-4444-4444-4444-444444444441';

update "group"
set
    city = 'New York',
    country_code = 'US',
    country_name = 'United States',
    external_payments_enabled = true,
    location = ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    state = 'New York'
where group_id = '44444444-4444-4444-4444-444444444448';

-- Social links for the gamma group used by public page breakpoint coverage.
update "group"
set website_url = 'https://example.com/e2e-observability-guild',
    twitter_url = 'https://twitter.com/e2e-observability'
where group_id = '44444444-4444-4444-4444-444444444443';

-- Backdate the beta group (which has a region) so community analytics group
-- running totals span more than one month (analytics_chart renders the empty
-- state otherwise).
update "group"
set created_at = now() - interval '3 months'
where group_id = '44444444-4444-4444-4444-444444444442';

-- Location for the gamma group so explore map view renders its marker.
update "group"
set city = 'Seattle',
    location = ST_SetSRID(ST_MakePoint(-122.3321, 47.6062), 4326)
where group_id = '44444444-4444-4444-4444-444444444443';
