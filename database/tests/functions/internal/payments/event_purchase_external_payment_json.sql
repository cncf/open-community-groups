-- Tests projecting a pending external payment into its enrollment JSON.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set eventPurchaseID 'e7a10000-0000-0000-0000-000000000001'
\set eventPurchaseWithoutDetailsID 'e7a10000-0000-0000-0000-000000000002'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should project the full external payment with an epoch deadline
select is(
    event_purchase_external_payment_json(
        jsonb_populate_record(null::event, jsonb_build_object(
            'external_payment_instructions', 'Wire the fee to the organizer bank account',
            'external_payment_url', 'https://pay.example.test/external-payment-json'
        )),
        jsonb_populate_record(null::event_purchase, jsonb_build_object(
            'amount_minor', 1500,
            'currency_code', 'USD',
            'event_purchase_id', :'eventPurchaseID',
            'hold_expires_at', '2024-01-01 00:00:00+00'
        ))
    ),
    jsonb_build_object(
        'amount_minor', 1500,
        'currency_code', 'USD',
        'deadline', 1704067200,
        'instructions', 'Wire the fee to the organizer bank account',
        'reference', :'eventPurchaseID',
        'url', 'https://pay.example.test/external-payment-json'
    ),
    'Should project the full external payment with an epoch deadline'
);

-- Should strip null instructions and url
select is(
    event_purchase_external_payment_json(
        jsonb_populate_record(null::event, '{}'::jsonb),
        jsonb_populate_record(null::event_purchase, jsonb_build_object(
            'amount_minor', 2500,
            'currency_code', 'EUR',
            'event_purchase_id', :'eventPurchaseWithoutDetailsID',
            'hold_expires_at', '2024-01-01 00:00:01+00'
        ))
    ),
    jsonb_build_object(
        'amount_minor', 2500,
        'currency_code', 'EUR',
        'deadline', 1704067201,
        'reference', :'eventPurchaseWithoutDetailsID'
    ),
    'Should strip null instructions and url'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
