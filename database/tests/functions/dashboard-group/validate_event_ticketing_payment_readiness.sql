-- Tests validating payment readiness for paid-capable ticket configuration.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept matching payment configuration for paid-capable events
select lives_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready"}'::jsonb
    )$$,
    'Should accept matching payment configuration for paid-capable events'
);

-- Should allow provider-free configuration for all-zero events
select lives_ok(
    $$select validate_event_ticketing_payment_readiness(null, false, null, null)$$,
    'Should allow provider-free configuration for all-zero events'
);

-- Should reject a missing payment currency for paid-capable events
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        null,
        '{"provider": "stripe", "recipient_id": "acct_ready"}'::jsonb
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
        '{"provider": "stripe", "recipient_id": "acct_ready"}'::jsonb
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
        '{"provider": "other", "recipient_id": "acct_ready"}'::jsonb
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
        '{"provider": "stripe", "recipient_id": " "}'::jsonb
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
        '{"provider": "stripe", "recipient_id": "acct_ready"}'::jsonb
    )$$,
    'payment_currency_code must be a supported currency code',
    'Should reject an unsupported payment currency for paid-capable events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
