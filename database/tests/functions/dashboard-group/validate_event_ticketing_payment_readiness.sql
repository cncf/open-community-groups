-- Tests validating payment readiness for paid-capable ticket configuration.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept matching payment configuration for paid-capable events
select lives_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        null,
        '{
            "kind_id": "in-person",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'Should accept matching payment configuration for paid-capable events'
);

-- Should accept paid-capable hybrid events with a complete physical venue
select lives_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        null,
        '{
            "kind_id": "hybrid",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state": "CA",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'Should accept paid-capable hybrid events with a complete physical venue'
);

-- Should allow provider-free configuration for all-zero events
select lives_ok(
    $$select validate_event_ticketing_payment_readiness(null, false, null, null)$$,
    'Should allow provider-free configuration for all-zero events'
);

-- Should reject paid-capable hybrid events with an incomplete physical venue
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        null,
        '{
            "kind_id": "hybrid",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall"
        }'::jsonb
    )$$,
    'paid ticketing requires an in-person or hybrid event with a complete physical venue',
    'Should reject paid-capable hybrid events with an incomplete physical venue'
);

-- Should reject a missing payment currency for paid-capable events
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        null,
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb
    )$$,
    'paid-capable events require payment_currency_code',
    'Should reject a missing payment currency for paid-capable events'
);

-- Should reject a missing payment recipient for paid-capable events
select throws_ok(
    $$select validate_event_ticketing_payment_readiness('stripe', true, 'USD', null)$$,
    'paid-capable events require a payment recipient',
    'Should reject a missing payment recipient for paid-capable events'
);

-- Should reject a missing server payment provider for paid-capable events
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        null,
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb
    )$$,
    'payments are not configured on this server',
    'Should reject a missing server payment provider for paid-capable events'
);

-- Should reject a recipient for another payment provider
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "other", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb
    )$$,
    'paid-capable events require a payment recipient for the server payments provider',
    'Should reject a recipient for another payment provider'
);

-- Should reject an empty recipient identifier
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": " ", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb
    )$$,
    'paid-capable events require a valid payment recipient',
    'Should reject an empty recipient identifier'
);

-- Should reject an unsupported payment currency for paid-capable events
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USDD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb
    )$$,
    'payment_currency_code must be a supported currency code',
    'Should reject an unsupported payment currency for paid-capable events'
);

-- Should reject a payment recipient without an attendee-visible seller name
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready"}'::jsonb
    )$$,
    'paid-capable events require a payment recipient seller name',
    'Should reject a payment recipient without a seller name'
);

-- Should reject paid-capable virtual events even when a physical venue is present
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        null,
        '{
            "kind_id": "virtual",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state": "CA",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'paid ticketing requires an in-person or hybrid event with a complete physical venue',
    'Should reject paid-capable virtual events even when a physical venue is present'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
