-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an omitted ticket types payload
select lives_ok(
    $$select validate_event_ticket_types_payload(null)$$,
    'Should accept an omitted ticket types payload'
);

-- Should accept valid ticket types
select lives_ok(
    $$select validate_event_ticket_types_payload(
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000061",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "ends_at": "2025-06-30 23:59:59+00",
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000071"
                    },
                    {
                        "amount_minor": 2500,
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000072",
                        "starts_at": "2025-07-01 00:00:00+00"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'Should accept valid ticket types'
);

-- Should reject overlapping ticket price windows
select throws_ok(
    $$select validate_event_ticket_types_payload(
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
        ]'::jsonb
    )$$,
    'ticket price windows cannot overlap',
    'Should reject overlapping ticket price windows'
);

-- Should reject ticket price windows without identifiers
select throws_ok(
    $$select validate_event_ticket_types_payload(
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000061",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'ticket price windows require event_ticket_price_window_id',
    'Should reject ticket price windows without identifiers'
);

-- Should reject ticket types without identifiers
select throws_ok(
    $$select validate_event_ticket_types_payload(
        '[
            {
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000071"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'ticket types require event_ticket_type_id',
    'Should reject ticket types without identifiers'
);

-- Should reject ticket types without title
select throws_ok(
    $$select validate_event_ticket_types_payload(
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000061",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000071"
                    }
                ],
                "seats_total": 50,
                "title": ""
            }
        ]'::jsonb
    )$$,
    'ticket types require title',
    'Should reject ticket types without title'
);

-- Should reject ticket types without seats_total
select throws_ok(
    $$select validate_event_ticket_types_payload(
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000061",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000071"
                    }
                ],
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'ticket types require seats_total',
    'Should reject ticket types without seats_total'
);

-- Should reject ticket types with negative seats_total values
select throws_ok(
    $$select validate_event_ticket_types_payload(
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000061",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000071"
                    }
                ],
                "seats_total": -1,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'ticket type seats_total must be greater than or equal to 0',
    'Should reject ticket types with negative seats_total values'
);

-- Should reject ticket types without price windows
select throws_ok(
    $$select validate_event_ticket_types_payload(
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000061",
                "order": 1,
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'ticket types require at least one price window',
    'Should reject ticket types without price windows'
);

-- Should reject ticket types with empty price windows
select throws_ok(
    $$select validate_event_ticket_types_payload(
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000061",
                "order": 1,
                "price_windows": [],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'ticket types require at least one price window',
    'Should reject ticket types with empty price windows'
);

-- Should reject ticket price windows without amount_minor
select throws_ok(
    $$select validate_event_ticket_types_payload(
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000061",
                "order": 1,
                "price_windows": [
                    {
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000071"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'ticket price windows must have non-negative amounts and valid date ranges',
    'Should reject ticket price windows without amount_minor'
);

-- Should reject ticket price windows with negative amount_minor
select throws_ok(
    $$select validate_event_ticket_types_payload(
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000061",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": -1,
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000071"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'ticket price windows must have non-negative amounts and valid date ranges',
    'Should reject ticket price windows with negative amount_minor'
);

-- Should reject ticket price windows with inverted date ranges
select throws_ok(
    $$select validate_event_ticket_types_payload(
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000061",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2000,
                        "ends_at": "2025-07-01 00:00:00+00",
                        "event_ticket_price_window_id": "00000000-0000-0000-0000-000000000071",
                        "starts_at": "2025-07-02 00:00:00+00"
                    }
                ],
                "seats_total": 50,
                "title": "General admission"
            }
        ]'::jsonb
    )$$,
    'ticket price windows must have non-negative amounts and valid date ranges',
    'Should reject ticket price windows with inverted date ranges'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
