-- Tests validating authoritative direct-charge checkout amounts.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a matching application fee
select lives_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1000,
                "provider_application_fee_id": "validate-direct-charge-checkout-amounts-fee-a",
                "tax_behavior": "inclusive",
                "tax_calculation_mode": "manual"
            }'::jsonb),
            1000,
            0,
            'validate-direct-charge-checkout-amounts-fee-a'
        )
    $$,
    'Should accept a matching application fee'
);

-- Should accept a missing reported fee when one is recorded
select lives_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1000,
                "provider_application_fee_id": "validate-direct-charge-checkout-amounts-fee-recorded",
                "tax_behavior": "inclusive",
                "tax_calculation_mode": "manual"
            }'::jsonb),
            1000,
            0,
            null
        )
    $$,
    'Should accept a missing reported fee when one is recorded'
);

-- Should accept valid exclusive amounts
select lives_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1000,
                "tax_behavior": "exclusive",
                "tax_calculation_mode": "manual"
            }'::jsonb),
            1100,
            100,
            null
        )
    $$,
    'Should accept valid exclusive amounts'
);

-- Should accept valid inclusive amounts
select lives_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1100,
                "tax_behavior": "inclusive",
                "tax_calculation_mode": "manual"
            }'::jsonb),
            1100,
            100,
            null
        )
    $$,
    'Should accept valid inclusive amounts'
);

-- Should reject an application fee mismatch
select throws_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1000,
                "provider_application_fee_id": "validate-direct-charge-checkout-amounts-fee-a",
                "tax_behavior": "inclusive",
                "tax_calculation_mode": "manual"
            }'::jsonb),
            1000,
            0,
            'validate-direct-charge-checkout-amounts-fee-b'
        )
    $$,
    'provider application fee does not match the purchase',
    'Should reject an application fee mismatch'
);

-- Should reject exclusive totals whose subtotal differs from the ticket
select throws_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1000,
                "tax_behavior": "exclusive",
                "tax_calculation_mode": "manual"
            }'::jsonb),
            1000,
            100,
            null
        )
    $$,
    'provider total does not match the ticket tax behavior',
    'Should reject exclusive totals whose subtotal differs from the ticket'
);

-- Should reject inclusive totals that differ from the ticket
select throws_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1000,
                "tax_behavior": "inclusive",
                "tax_calculation_mode": "manual"
            }'::jsonb),
            1100,
            100,
            null
        )
    $$,
    'provider total does not match the ticket tax behavior',
    'Should reject inclusive totals that differ from the ticket'
);

-- Should reject negative subtotal amounts
select throws_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1000,
                "tax_behavior": "inclusive",
                "tax_calculation_mode": "manual"
            }'::jsonb),
            100,
            101,
            null
        )
    $$,
    'direct-charge checkout is missing authoritative amounts',
    'Should reject negative subtotal amounts'
);

-- Should reject negative tax amounts
select throws_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1000,
                "tax_behavior": "inclusive",
                "tax_calculation_mode": "manual"
            }'::jsonb),
            1000,
            -1,
            null
        )
    $$,
    'direct-charge checkout is missing authoritative amounts',
    'Should reject negative tax amounts'
);

-- Should reject no-tax checkouts with provider tax
select throws_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1000,
                "tax_behavior": "inclusive",
                "tax_calculation_mode": "none"
            }'::jsonb),
            1000,
            1,
            null
        )
    $$,
    'no-tax checkout must have zero tax',
    'Should reject no-tax checkouts with provider tax'
);

-- Should reject null tax amounts
select throws_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1000,
                "tax_behavior": "inclusive",
                "tax_calculation_mode": "manual"
            }'::jsonb),
            1000,
            null,
            null
        )
    $$,
    'direct-charge checkout is missing authoritative amounts',
    'Should reject null tax amounts'
);

-- Should reject null total amounts
select throws_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1000,
                "tax_behavior": "inclusive",
                "tax_calculation_mode": "manual"
            }'::jsonb),
            null,
            0,
            null
        )
    $$,
    'direct-charge checkout is missing authoritative amounts',
    'Should reject null total amounts'
);

-- Should reject zero total amounts
select throws_ok(
    $$
        select validate_direct_charge_checkout_amounts(
            jsonb_populate_record(null::event_purchase, '{
                "amount_minor": 1000,
                "tax_behavior": "inclusive",
                "tax_calculation_mode": "manual"
            }'::jsonb),
            0,
            0,
            null
        )
    $$,
    'direct-charge checkout is missing authoritative amounts',
    'Should reject zero total amounts'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
