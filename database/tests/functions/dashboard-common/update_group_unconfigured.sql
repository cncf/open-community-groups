-- Tests updating group payment recipients without operator external-payments config.
-- Split from update_group.sql because that file seeds the singleton
-- external_payments_config row this scenario requires to be absent.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1c030000-0000-0000-0000-000000000001'
\set groupCategoryID '1c030000-0000-0000-0000-000000000002'
\set groupID '1c030000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and group categories
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group in a country that no absent operator config can allowlist
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'name', 'Unconfigured External Payments Group'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow adding a fiscal sponsor when no operator config row is synced
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Unconfigured External Payments Group",
            "category_id": "%s",
            "country_code": "KR",
            "_payment_validation": {
                "expected_payment_recipient": null,
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_unconfigured",
                    "seller_display_name": "Unconfigured Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_unconfigured",
                "seller_display_name": "Unconfigured Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupID',
        :'groupCategoryID'
    ),
    'Should allow adding a fiscal sponsor when no operator config row is synced'
);

-- Should persist the fiscal sponsor added without operator config
select is(
    (select get_group_full(:'communityID'::uuid, :'groupID'::uuid)::jsonb->'payment_recipient'),
    '{
        "provider": "stripe",
        "recipient_id": "acct_unconfigured",
        "seller_display_name": "Unconfigured Fiscal Sponsor"
    }'::jsonb,
    'Should persist the fiscal sponsor added without operator config'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
