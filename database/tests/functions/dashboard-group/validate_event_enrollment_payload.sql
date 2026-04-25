-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept default enrollment settings
select lives_ok(
    $$select validate_event_enrollment_payload(false, null, false)$$,
    'Should accept default enrollment settings'
);

-- Should reject waitlists for approval-required events
select throws_ok(
    $$select validate_event_enrollment_payload(true, null, true)$$,
    'approval-required events cannot enable waitlist',
    'Should reject waitlists for approval-required events'
);

-- Should reject ticketing for approval-required events
select throws_ok(
    $$select validate_event_enrollment_payload(
        true,
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
    'approval-required events cannot be ticketed',
    'Should reject ticketing for approval-required events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
