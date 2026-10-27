-- Tests validating event ticketing payloads.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

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

-- Resolved event rows: a Korean venue on the external rail and a complete
-- US venue with automatic tax on the Stripe rail
create temporary table test_event (external_event event not null, stripe_event event not null);
insert into test_event (
    external_event.event_kind_id,
    external_event.external_payment_url,
    external_event.manual_tax_rate_ids,
    external_event.payment_currency_code,
    external_event.tax_behavior,
    external_event.tax_calculation_mode,
    external_event.venue_address,
    external_event.venue_city,
    external_event.venue_country_code,
    external_event.venue_name,
    external_event.venue_zip_code,
    stripe_event.event_kind_id,
    stripe_event.manual_tax_rate_ids,
    stripe_event.payment_currency_code,
    stripe_event.tax_behavior,
    stripe_event.tax_calculation_mode,
    stripe_event.venue_address,
    stripe_event.venue_city,
    stripe_event.venue_country_code,
    stripe_event.venue_name,
    stripe_event.venue_state_code,
    stripe_event.venue_zip_code
) values (
    'in-person',
    'https://pay.example.test/ready',
    array[]::text[],
    'KRW',
    'inclusive',
    'automatic',
    '1 Test Street',
    'Seoul',
    'KR',
    'Test Hall',
    '00000',
    'in-person',
    array[]::text[],
    'USD',
    'inclusive',
    'automatic',
    '123 Main St',
    'San Francisco',
    'US',
    'Community Hall',
    'CA',
    '94105'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a Stripe-ready paid payload
select lives_ok(
    $$select validate_event_ticketing_payload(
        'stripe',
        null,
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
        (select t.stripe_event from test_event t),
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        false,
        null,
        true
    )$$,
    'Should accept a Stripe-ready paid payload'
);

-- Should accept all-zero ticketing without payment configuration
select lives_ok(
    $$select validate_event_ticketing_payload(
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
        ]'::jsonb,
        (select jsonb_populate_record(t.stripe_event, '{"payment_currency_code": null}'::jsonb) from test_event t),
        null,
        false,
        null,
        true
    )$$,
    'Should accept all-zero ticketing without payment configuration'
);

-- Should accept paid-capable external mode without a Stripe recipient
select lives_ok(
    $$select validate_event_ticketing_payload(
        null,
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
        (select t.external_event from test_event t),
        null,
        true,
        'KR',
        true
    )$$,
    'Should accept paid-capable external mode without a Stripe recipient'
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
        (select t.stripe_event from test_event t),
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        false,
        null,
        true
    )$$,
    'OCG01',
    'discount codes must be unique per event',
    'Should delegate discount code validation'
);

-- Should delegate ticket type validation
select throws_ok(
    $$select validate_event_ticketing_payload(
        'stripe',
        null,
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
        ]'::jsonb,
        (select t.stripe_event from test_event t),
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        false,
        null,
        true
    )$$,
    'OCG01',
    'ticket price windows cannot overlap',
    'Should delegate ticket type validation'
);

-- Should reject a paid-capable external event with a venue outside the group country
select throws_ok(
    $$select validate_event_ticketing_payload(
        null,
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
        (
            select jsonb_populate_record(t.external_event, '{
                "venue_city": "Tokyo",
                "venue_country_code": "JP",
                "venue_zip_code": "100-0001"
            }'::jsonb)
            from test_event t
        ),
        null,
        true,
        'KR',
        true
    )$$,
    'OCG01',
    'external paid events require a venue in the group country',
    'Should reject a paid-capable external event with a venue outside the group country'
);

-- Should reject non-zero ticket prices below Stripe minimums
select throws_ok(
    $$select validate_event_ticketing_payload(
        'stripe',
        null,
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
        (select t.stripe_event from test_event t),
        '{"provider": "stripe", "recipient_id": "acct_ready", "seller_display_name": "Ready Fiscal Sponsor"}'::jsonb,
        false,
        null,
        true
    )$$,
    'OCG01',
    'payment amount must be zero or at least Stripe minimum charge amount',
    'Should reject non-zero ticket prices below Stripe minimums'
);

-- Should require positive ticket pricing when a payment currency is present
select throws_ok(
    $$select validate_event_ticketing_payload(
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
        ]'::jsonb,
        (select t.stripe_event from test_event t),
        null,
        false,
        null,
        true
    )$$,
    'OCG01',
    'payment_currency_code requires positive ticket pricing',
    'Should require positive ticket pricing when a payment currency is present'
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
        ]'::jsonb,
        (select jsonb_populate_record(t.stripe_event, '{"payment_currency_code": null}'::jsonb) from test_event t),
        null,
        false,
        null,
        true
    )$$,
    'OCG01',
    'discount_codes require positive ticket pricing',
    'Should require positive ticket pricing when discount codes are present'
);

-- Should skip payment configuration checks when validation is disabled
select lives_ok(
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
        ]'::jsonb,
        (select t.stripe_event from test_event t),
        null,
        false,
        null,
        false
    )$$,
    'Should skip payment configuration checks when validation is disabled'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
