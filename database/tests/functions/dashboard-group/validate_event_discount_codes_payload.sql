-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an omitted discount codes payload
select lives_ok(
    $$select validate_event_discount_codes_payload(null)$$,
    'Should accept an omitted discount codes payload'
);

-- Should accept valid discount codes
select lives_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "amount_minor": 500,
                "code": "SAVE5",
                "kind": "fixed_amount",
                "title": "Launch discount"
            },
            {
                "event_discount_code_id": "00000000-0000-0000-0000-000000000052",
                "code": "SAVE15",
                "kind": "percentage",
                "percentage": 15,
                "title": "Alpha discount"
            }
        ]'::jsonb
    )$$,
    'Should accept valid discount codes'
);

-- Should reject duplicate discount codes
select throws_ok(
    $$select validate_event_discount_codes_payload(
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
        ]'::jsonb
    )$$,
    'discount codes must be unique per event',
    'Should reject duplicate discount codes'
);

-- Should reject discount codes with available values above total_available
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "available": 11,
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "amount_minor": 500,
                "code": "SAVE5",
                "kind": "fixed_amount",
                "title": "Launch discount",
                "total_available": 10
            }
        ]'::jsonb
    )$$,
    'discount code available cannot exceed total_available',
    'Should reject discount codes with available values above total_available'
);

-- Should reject discount codes without identifiers
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "amount_minor": 500,
                "code": "SAVE5",
                "kind": "fixed_amount",
                "title": "Launch discount"
            }
        ]'::jsonb
    )$$,
    'discount codes require event_discount_code_id',
    'Should reject discount codes without identifiers'
);

-- Should reject discount codes without code
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "amount_minor": 500,
                "code": "",
                "kind": "fixed_amount",
                "title": "Launch discount"
            }
        ]'::jsonb
    )$$,
    'discount codes require code',
    'Should reject discount codes without code'
);

-- Should reject discount codes without title
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "amount_minor": 500,
                "code": "SAVE5",
                "kind": "fixed_amount",
                "title": ""
            }
        ]'::jsonb
    )$$,
    'discount codes require title',
    'Should reject discount codes without title'
);

-- Should reject discount codes with negative available values
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "available": -1,
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "amount_minor": 500,
                "code": "SAVE5",
                "kind": "fixed_amount",
                "title": "Launch discount"
            }
        ]'::jsonb
    )$$,
    'discount code available must be greater than or equal to 0',
    'Should reject discount codes with negative available values'
);

-- Should reject discount codes with negative total_available values
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "amount_minor": 500,
                "code": "SAVE5",
                "kind": "fixed_amount",
                "title": "Launch discount",
                "total_available": -1
            }
        ]'::jsonb
    )$$,
    'discount code total_available must be greater than or equal to 0',
    'Should reject discount codes with negative total_available values'
);

-- Should reject discount codes with inverted date ranges
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "ends_at": "2025-06-01 00:00:00+00",
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "amount_minor": 500,
                "code": "SAVE5",
                "kind": "fixed_amount",
                "starts_at": "2025-06-15 00:00:00+00",
                "title": "Launch discount"
            }
        ]'::jsonb
    )$$,
    'discount code ends_at cannot be before starts_at',
    'Should reject discount codes with inverted date ranges'
);

-- Should reject fixed amount discount codes without amount_minor
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "code": "SAVE5",
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "kind": "fixed_amount",
                "title": "Launch discount"
            }
        ]'::jsonb
    )$$,
    'fixed amount discount codes require amount_minor',
    'Should reject fixed amount discount codes without amount_minor'
);

-- Should reject fixed amount discount codes with negative amount_minor
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "amount_minor": -1,
                "code": "SAVE5",
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "kind": "fixed_amount",
                "title": "Launch discount"
            }
        ]'::jsonb
    )$$,
    'discount code amount_minor must be greater than or equal to 0',
    'Should reject fixed amount discount codes with negative amount_minor'
);

-- Should reject fixed amount discount codes with percentage values
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "amount_minor": 500,
                "code": "SAVE5",
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "kind": "fixed_amount",
                "percentage": 15,
                "title": "Launch discount"
            }
        ]'::jsonb
    )$$,
    'fixed amount discount codes cannot include percentage',
    'Should reject fixed amount discount codes with percentage values'
);

-- Should reject percentage discount codes without percentage
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "code": "SAVE15",
                "event_discount_code_id": "00000000-0000-0000-0000-000000000052",
                "kind": "percentage",
                "title": "Alpha discount"
            }
        ]'::jsonb
    )$$,
    'percentage discount codes require percentage',
    'Should reject percentage discount codes without percentage'
);

-- Should reject percentage discount codes below the allowed range
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "code": "SAVE0",
                "event_discount_code_id": "00000000-0000-0000-0000-000000000052",
                "kind": "percentage",
                "percentage": 0,
                "title": "Alpha discount"
            }
        ]'::jsonb
    )$$,
    'discount percentage must be between 1 and 100',
    'Should reject percentage discount codes below the allowed range'
);

-- Should reject percentage discount codes above the allowed range
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "code": "SAVE101",
                "event_discount_code_id": "00000000-0000-0000-0000-000000000052",
                "kind": "percentage",
                "percentage": 101,
                "title": "Alpha discount"
            }
        ]'::jsonb
    )$$,
    'discount percentage must be between 1 and 100',
    'Should reject percentage discount codes above the allowed range'
);

-- Should reject percentage discount codes with amount_minor values
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "amount_minor": 500,
                "code": "SAVE15",
                "event_discount_code_id": "00000000-0000-0000-0000-000000000052",
                "kind": "percentage",
                "percentage": 15,
                "title": "Alpha discount"
            }
        ]'::jsonb
    )$$,
    'percentage discount codes cannot include amount_minor',
    'Should reject percentage discount codes with amount_minor values'
);

-- Should reject discount codes with invalid kind values
select throws_ok(
    $$select validate_event_discount_codes_payload(
        '[
            {
                "code": "SAVE5",
                "event_discount_code_id": "00000000-0000-0000-0000-000000000051",
                "kind": "bogus",
                "title": "Launch discount"
            }
        ]'::jsonb
    )$$,
    'discount codes require a valid kind',
    'Should reject discount codes with invalid kind values'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
