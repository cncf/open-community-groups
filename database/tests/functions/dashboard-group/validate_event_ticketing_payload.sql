-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an omitted ticketing payload
select lives_ok(
    $$select validate_event_ticketing_payload(null, null, null, null, null)$$,
    'Should accept an omitted ticketing payload'
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
        '{"provider": "stripe", "recipient_id": "acct_ready"}'::jsonb,
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
    'Should accept waitlists for ticketed events'
);

-- Should require a payment currency for ticketed events
select throws_ok(
    $$select validate_event_ticketing_payload(
        'stripe',
        null,
        null,
        '{"provider": "stripe", "recipient_id": "acct_ready"}'::jsonb,
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

-- Should reject unsupported payment currencies for ticketed events
select throws_ok(
    $$select validate_event_ticketing_payload(
        'stripe',
        null,
        'USDD',
        '{"provider": "stripe", "recipient_id": "acct_ready"}'::jsonb,
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
        '{"provider": "stripe", "recipient_id": "acct_ready"}'::jsonb,
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

-- Should require ticket types when discount codes are present
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
        null
    )$$,
    'discount_codes require positive ticket pricing',
    'Should require positive ticket pricing when discount codes are present'
);

-- Should require ticket types when a payment currency is present
select throws_ok(
    $$select validate_event_ticketing_payload(
        null,
        null,
        'USD',
        null,
        null
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
        '{"provider": "stripe", "recipient_id": "acct_ready"}'::jsonb,
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
        '{"provider": "stripe", "recipient_id": "acct_ready"}'::jsonb,
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
        ]'::jsonb
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
        '{"provider": "stripe", "recipient_id": "acct_ready"}'::jsonb,
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
        ]'::jsonb
    )$$,
    'payment amount exceeds Stripe maximum charge amount',
    'Should reject ticket prices above Stripe maximums'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
