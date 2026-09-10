-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set ticketTypeAID '3a100000-0000-0000-0000-000000000001'
\set ticketTypeBID '3a100000-0000-0000-0000-000000000002'
\set ticketTypeCID '3a100000-0000-0000-0000-000000000003'

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
        format(
            '[
            {
                "event_ticket_type_id": "%s",
                "seats_total": 50
            },
            {
                "event_ticket_type_id": "%s",
                "seats_total": -10
            },
            {
                "event_ticket_type_id": "%s",
                "seats_total": 25
            }
        ]',
            :'ticketTypeAID', :'ticketTypeBID', :'ticketTypeCID'
        )::jsonb
    ),
    75,
    'Should sum only non-negative seats across ticket types'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
