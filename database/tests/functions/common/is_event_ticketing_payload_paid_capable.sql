-- Tests detecting paid-capable ticket configuration payloads.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should detect positive prices regardless of tier state or window timing
select is(
    is_event_ticketing_payload_paid_capable(
        '[
            {
                "active": false,
                "price_windows": [
                    {
                        "amount_minor": 2500,
                        "starts_at": "2030-01-01 00:00:00+00"
                    }
                ]
            }
        ]'::jsonb
    ),
    true,
    'Should detect positive prices regardless of tier state or window timing'
);

-- Should return false for an omitted ticket configuration
select is(
    is_event_ticketing_payload_paid_capable(null),
    false,
    'Should return false for an omitted ticket configuration'
);

-- Should return false when every configured price is zero
select is(
    is_event_ticketing_payload_paid_capable(
        '[
            {
                "price_windows": [
                    {"amount_minor": 0},
                    {"amount_minor": 0}
                ]
            }
        ]'::jsonb
    ),
    false,
    'Should return false when every configured price is zero'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
