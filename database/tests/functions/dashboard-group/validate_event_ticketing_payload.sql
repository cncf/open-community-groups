-- Tests validating event ticketing payloads.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Operator allowlist used by external-mode payload scenarios
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

-- Should reject an omitted ticket inventory
select throws_ok(
    $$select validate_event_ticketing_payload(null, null, null, null, null)$$,
    'events require at least one ticket type',
    'Should reject an omitted ticket inventory'
);

-- Should accept all-zero ticketing without payment configuration
select lives_ok(
    $$select validate_event_ticketing_payload(
        null,
        null,
        null,
        null,
        '[
            {
                "event_ticket_type_id": "3a470000-0000-0000-0000-000000000003",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 0,
                        "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000005"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'Should accept all-zero ticketing without payment configuration'
);

-- Should accept waitlists for ticketed events
select lives_ok(
    $$select validate_event_ticketing_payload(
        'stripe',
        null,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        '[
            {
                "event_ticket_type_id": "3a470000-0000-0000-0000-000000000003",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000005"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb,
        true,
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
    'Should accept waitlists for ticketed events'
);

-- Should accept paid-capable external mode without a Stripe recipient
select lives_ok(
    $$select validate_event_ticketing_payload(
        null,
        null,
        'KRW',
        null,
        '[
            {
                "event_ticket_type_id": "3a470000-0000-0000-0000-000000000003",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 5000,
                        "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000005"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb,
        true,
        null,
        '{
            "external_mode": true,
            "external_payment_url": "https://pay.example.test/ready",
            "kind_id": "in-person",
            "venue_address": "1 Test Street",
            "venue_city": "Seoul",
            "venue_country_code": "KR",
            "venue_name": "Test Hall",
            "venue_zip_code": "00000"
        }'::jsonb
    )$$,
    'Should accept paid-capable external mode without a Stripe recipient'
);

-- Should require a payment currency for ticketed events
select throws_ok(
    $$select validate_event_ticketing_payload(
        'stripe',
        null,
        null,
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        '[
            {
                "event_ticket_type_id": "3a470000-0000-0000-0000-000000000003",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000005"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'paid-capable events require payment_currency_code',
    'Should require a payment currency for paid-capable events'
);

-- Should reject a paid-capable external event without a payment URL
select throws_ok(
    $$select validate_event_ticketing_payload(
        null,
        null,
        'KRW',
        null,
        '[
            {
                "event_ticket_type_id": "3a470000-0000-0000-0000-000000000003",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 5000,
                        "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000005"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb,
        true,
        null,
        '{
            "external_mode": true,
            "kind_id": "in-person",
            "venue_address": "1 Test Street",
            "venue_city": "Seoul",
            "venue_country_code": "KR",
            "venue_name": "Test Hall",
            "venue_zip_code": "00000"
        }'::jsonb
    )$$,
    'paid-capable events require a valid external payment url',
    'Should reject a paid-capable external event without a payment URL'
);

-- Should reject unsupported payment currencies for ticketed events
select throws_ok(
    $$select validate_event_ticketing_payload(
        'stripe',
        null,
        'USDD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        '[
            {
                "event_ticket_type_id": "3a470000-0000-0000-0000-000000000003",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000005"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'payment_currency_code must be a supported currency code',
    'Should reject unsupported payment currencies for ticketed events'
);

-- Should delegate discount code validation
select throws_ok(
    $$select validate_event_ticketing_payload(
        'stripe',
        '[
            {
                "event_discount_code_id": "3a470000-0000-0000-0000-000000000001",
                "amount_minor": 500,
                "code": "save5",
                "kind": "fixed_amount",
                "title": "Launch discount"
            },
            {
                "event_discount_code_id": "3a470000-0000-0000-0000-000000000002",
                "amount_minor": 1000,
                "code": "SAVE5",
                "kind": "fixed_amount",
                "title": "VIP discount"
            }
        ]'::jsonb,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        '[
            {
                "event_ticket_type_id": "3a470000-0000-0000-0000-000000000003",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000005"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'discount codes must be unique per event',
    'Should delegate discount code validation'
);

-- Should require positive ticket pricing when discount codes are present
select throws_ok(
    $$select validate_event_ticketing_payload(
        null,
        '[
            {
                "event_discount_code_id": "3a470000-0000-0000-0000-000000000001",
                "amount_minor": 500,
                "code": "save5",
                "kind": "fixed_amount",
                "title": "Launch discount"
            }
        ]'::jsonb,
        null,
        null,
        '[{
            "event_ticket_type_id": "3a470000-0000-0000-0000-000000000003",
            "order": 1,
            "price_windows": [{
                "amount_minor": 0,
                "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000005"
            }],
            "seats_total": 50,
            "title": "General admission"
        }]'::jsonb
    )$$,
    'discount_codes require positive ticket pricing',
    'Should require positive ticket pricing when discount codes are present'
);

-- Should require positive ticket pricing when a payment currency is present
select throws_ok(
    $$select validate_event_ticketing_payload(
        null,
        null,
        'USD',
        null,
        '[{
            "event_ticket_type_id": "3a470000-0000-0000-0000-000000000003",
            "order": 1,
            "price_windows": [{
                "amount_minor": 0,
                "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000005"
            }],
            "seats_total": 50,
            "title": "General admission"
        }]'::jsonb
    )$$,
    'payment_currency_code requires positive ticket pricing',
    'Should require positive ticket pricing when a payment currency is present'
);

-- Should delegate ticket type validation
select throws_ok(
    $$select validate_event_ticketing_payload(
        'stripe',
        null,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        '[
            {
                "event_ticket_type_id": "3a470000-0000-0000-0000-000000000004",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "ends_at": "2025-07-10 00:00:00+00",
                        "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000006",
                        "starts_at": "2025-07-01 00:00:00+00"
                    },
                    {
                        "amount_minor": 2500,
                        "ends_at": "2025-07-15 00:00:00+00",
                        "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000007",
                        "starts_at": "2025-07-05 00:00:00+00"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'ticket price windows cannot overlap',
    'Should delegate ticket type validation'
);

-- Should reject non-zero ticket prices below minimums
select throws_ok(
    $$select validate_event_ticketing_payload(
        'stripe',
        null,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        '[
            {
                "event_ticket_type_id": "3a470000-0000-0000-0000-000000000004",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 49,
                        "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000006"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb,
        true,
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
    'payment amount must be zero or at least Stripe minimum charge amount',
    'Should reject non-zero ticket prices below Stripe minimums'
);

-- Should reject ticket prices above maximums
select throws_ok(
    $$select validate_event_ticketing_payload(
        'stripe',
        null,
        'USD',
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        '[
            {
                "event_ticket_type_id": "3a470000-0000-0000-0000-000000000004",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 100000000,
                        "event_ticket_price_window_id": "3a470000-0000-0000-0000-000000000006"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb,
        true,
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
    'payment amount exceeds Stripe maximum charge amount',
    'Should reject ticket prices above Stripe maximums'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
