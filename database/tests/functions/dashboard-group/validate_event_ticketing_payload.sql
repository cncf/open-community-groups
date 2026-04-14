-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an omitted ticketing payload
select lives_ok(
    $$select validate_event_ticketing_payload(null, null, null, false)$$,
    'Should accept an omitted ticketing payload'
);

-- Should reject waitlists for ticketed events
select throws_ok(
    $$select validate_event_ticketing_payload(
        null,
        'USD',
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000060",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000070"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb,
        true
    )$$,
    'waitlist cannot be enabled for ticketed events',
    'Should reject waitlists for ticketed events'
);

-- Should require a payment currency for ticketed events
select throws_ok(
    $$select validate_event_ticketing_payload(
        null,
        null,
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000060",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000070"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb,
        false
    )$$,
    'ticketed events require payment_currency_code',
    'Should require a payment currency for ticketed events'
);

-- Should delegate discount code validation
select throws_ok(
    $$select validate_event_ticketing_payload(
        '[
            {
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "amount_minor": 500,
                "code": "save5",
                "kind": "fixed_amount",
                "title": "Launch discount"
            },
            {
                "event_discount_code_id": "00000000-0000-0000-0000-000000000052",
                "amount_minor": 1000,
                "code": "SAVE5",
                "kind": "fixed_amount",
                "title": "VIP discount"
            }
        ]'::jsonb,
        'USD',
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000060",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000070"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb,
        false
    )$$,
    'discount codes must be unique per event',
    'Should delegate discount code validation'
);

-- Should require ticket types when discount codes are present
select throws_ok(
    $$select validate_event_ticketing_payload(
        '[
            {
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "amount_minor": 500,
                "code": "save5",
                "kind": "fixed_amount",
                "title": "Launch discount"
            }
        ]'::jsonb,
        null,
        null,
        false
    )$$,
    'discount_codes require ticket_types',
    'Should require ticket types when discount codes are present'
);

-- Should require ticket types when a payment currency is present
select throws_ok(
    $$select validate_event_ticketing_payload(
        null,
        'USD',
        null,
        false
    )$$,
    'payment_currency_code requires ticket_types',
    'Should require ticket types when a payment currency is present'
);

-- Should delegate ticket type validation
select throws_ok(
    $$select validate_event_ticketing_payload(
        null,
        'USD',
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000061",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "ends_at": "2025-07-10 00:00:00+00",
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000071",
                        "starts_at": "2025-07-01 00:00:00+00"
                    },
                    {
                        "amount_minor": 2500,
                        "ends_at": "2025-07-15 00:00:00+00",
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000072",
                        "starts_at": "2025-07-05 00:00:00+00"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb,
        false
    )$$,
    'ticket price windows cannot overlap',
    'Should delegate ticket type validation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
