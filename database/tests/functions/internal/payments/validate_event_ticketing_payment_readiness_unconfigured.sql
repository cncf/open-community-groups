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
        null,
        '{
            "kind_id": "in-person",
            "venue_address": "1 Test Street",
            "venue_city": "Seoul",
            "venue_country_code": "KR",
            "venue_name": "Test Hall",
            "venue_zip_code": "00000"
        }'::jsonb,
        true,
        'https://pay.example.test/unconfigured',
        null,
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
