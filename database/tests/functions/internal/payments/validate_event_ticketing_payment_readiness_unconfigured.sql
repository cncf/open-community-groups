-- Tests rejecting external payment readiness without operator configuration.
-- Split from validate_event_ticketing_payment_readiness.sql because the
-- external_payments_config singleton seeded there must be absent here.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject external mode when external payments are not configured
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        null,
        true,
        'KRW',
        null,
        jsonb_populate_record(null::event, '{
            "event_kind_id": "in-person",
            "external_payment_url": "https://pay.example.test/unconfigured",
            "manual_tax_rate_ids": [],
            "payment_currency_code": "KRW",
            "tax_behavior": "inclusive",
            "tax_calculation_mode": "automatic",
            "venue_address": "1 Test Street",
            "venue_city": "Seoul",
            "venue_country_code": "KR",
            "venue_name": "Test Hall",
            "venue_zip_code": "00000"
        }'::jsonb),
        true,
        'KR'
    )$$,
    'OCG01',
    'external payments are not configured on this server',
    'Should reject external mode when external payments are not configured'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
