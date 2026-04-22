-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an omitted ticket types payload
select is(
    get_event_ticket_capacity(null),
    null,
    'Should accept an omitted ticket types payload'
);

-- Should return zero for an empty ticket types payload
select is(
    get_event_ticket_capacity('[]'::jsonb),
    0,
    'Should return zero for an empty ticket types payload'
);

-- Should sum only non-negative seats across ticket types
select is(
    get_event_ticket_capacity(
        '[
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000061",
                "seats_total": 50
            },
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000062",
                "seats_total": -10
            },
            {
                "event_ticket_type_id": "00000000-0000-0000-0000-000000000063",
                "seats_total": 25
            }
        ]'::jsonb
    ),
    75,
    'Should sum only non-negative seats across ticket types'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
