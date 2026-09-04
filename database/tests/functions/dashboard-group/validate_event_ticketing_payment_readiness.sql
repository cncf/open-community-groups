-- Tests validating payment readiness for paid-capable ticket configuration.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(31);

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Operator allowlist and window limits used by external-mode readiness scenarios
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

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
            "venue_state_code": "CA",
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
            "venue_state_code": "CA",
            "venue_state_name": "California",
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

-- Should accept multiple manual Tax Rates for paid events
select lives_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        null,
        '{
            "kind_id": "in-person",
            "manual_tax_rate_ids": ["txr_state", "txr_local"],
            "tax_behavior": "exclusive",
            "tax_calculation_mode": "manual",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'Should accept multiple manual Tax Rates for paid events'
);

-- Should reject paid manual-tax events without a selected rate
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        null,
        '{
            "kind_id": "in-person",
            "tax_calculation_mode": "manual",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'manual ticket tax requires at least one unique Stripe Tax Rate',
    'Should reject paid manual-tax events without a selected rate'
);

-- Should reject duplicate manual Tax Rate identifiers
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        null,
        '{
            "kind_id": "in-person",
            "manual_tax_rate_ids": ["txr_state", "txr_state"],
            "tax_calculation_mode": "manual",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'manual ticket tax requires at least one unique Stripe Tax Rate',
    'Should reject duplicate manual Tax Rate identifiers'
);

-- Should reject manual Tax Rate identifiers with surrounding whitespace
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        null,
        '{
            "kind_id": "in-person",
            "manual_tax_rate_ids": [" txr_state "],
            "tax_calculation_mode": "manual",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'manual ticket tax requires at least one unique Stripe Tax Rate',
    'Should reject manual Tax Rate identifiers with surrounding whitespace'
);

-- Should reject manual Tax Rate identifiers in automatic mode
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        null,
        '{
            "kind_id": "in-person",
            "manual_tax_rate_ids": ["txr_stale"],
            "tax_calculation_mode": "automatic",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'automatic ticket tax cannot include manual Tax Rates',
    'Should reject manual Tax Rate identifiers in automatic mode'
);

-- Should accept an explicitly normalized no-tax event
select lives_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        null,
        '{
            "kind_id": "in-person",
            "manual_tax_rate_ids": [],
            "tax_behavior": "inclusive",
            "tax_calculation_mode": "none",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'Should accept an explicitly normalized no-tax event'
);

-- Should reject exclusive display for no-tax events
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        'stripe',
        true,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        null,
        '{
            "kind_id": "in-person",
            "manual_tax_rate_ids": [],
            "tax_behavior": "exclusive",
            "tax_calculation_mode": "none",
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'events that do not collect tax require inclusive display and no Tax Rates',
    'Should reject exclusive display for no-tax events'
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

-- Should accept a missing state code for automatic ticket tax
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
    'Should accept a missing state code for automatic ticket tax'
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
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'paid ticketing requires an in-person or hybrid event with a complete physical venue',
    'Should reject paid-capable virtual events even when a physical venue is present'
);

-- Should accept external mode without a Stripe recipient when the URL is valid
select lives_ok(
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
        'https://pay.example.test/ready',
        null,
        'KR'
    )$$,
    'Should accept external mode without a Stripe recipient when the URL is valid'
);

-- Should accept an external venue whose country matches the group country in another case
select lives_ok(
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
            "venue_country_code": "kr",
            "venue_name": "Test Hall",
            "venue_zip_code": "00000"
        }'::jsonb,
        true,
        'https://pay.example.test/case',
        null,
        ' KR '
    )$$,
    'Should accept an external venue whose country matches the group country in another case'
);

-- Should accept an external payment window within the configured maximum
select lives_ok(
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
        'https://pay.example.test/window',
        168,
        'KR'
    )$$,
    'Should accept an external payment window within the configured maximum'
);

-- Should reject external fields on unpaid events
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        null,
        false,
        null,
        null,
        null,
        null,
        true,
        'https://pay.example.test/unpaid',
        null
    )$$,
    'external payment fields require paid-capable ticketing',
    'Should reject external fields on unpaid events'
);

-- Should reject external fields when the group is not in external mode
select throws_ok(
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
        }'::jsonb,
        false,
        'https://pay.example.test/leftover',
        null
    )$$,
    'external payment fields require external payments mode',
    'Should reject external fields when the group is not in external mode'
);

-- Should reject external mode without a valid payment URL
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
        'ftp://pay.example.test/invalid',
        null
    )$$,
    'paid-capable events require a valid external payment url',
    'Should reject external mode without a valid payment URL'
);

-- Should reject an external payment window above the configured maximum
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
        'https://pay.example.test/window',
        337
    )$$,
    'external payment window exceeds the configured maximum',
    'Should reject an external payment window above the configured maximum'
);

-- Should reject paid external virtual events even with a complete venue
select throws_ok(
    $$select validate_event_ticketing_payment_readiness(
        null,
        true,
        'KRW',
        null,
        null,
        '{
            "kind_id": "virtual",
            "venue_address": "1 Test Street",
            "venue_city": "Seoul",
            "venue_country_code": "KR",
            "venue_name": "Test Hall",
            "venue_zip_code": "00000"
        }'::jsonb,
        true,
        'https://pay.example.test/virtual',
        null
    )$$,
    'paid ticketing requires an in-person or hybrid event with a complete physical venue',
    'Should reject paid external virtual events even with a complete venue'
);

-- Should reject paid external mode when the payment URL is missing
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
        null,
        null
    )$$,
    'paid-capable events require a valid external payment url',
    'Should reject paid external mode when the payment URL is missing'
);

-- Should reject paid external events with a venue outside the group country
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
            "venue_city": "Tokyo",
            "venue_country_code": "JP",
            "venue_name": "Test Hall",
            "venue_zip_code": "100-0001"
        }'::jsonb,
        true,
        'https://pay.example.test/abroad',
        null,
        'KR'
    )$$,
    'external paid events require a venue in the group country',
    'Should reject paid external events with a venue outside the group country'
);

-- Should reject paid external events when the group country is unknown
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
        'https://pay.example.test/no-country',
        null,
        null
    )$$,
    'external paid events require a venue in the group country',
    'Should reject paid external events when the group country is unknown'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
