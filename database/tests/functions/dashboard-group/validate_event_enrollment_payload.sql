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
    $$select validate_event_enrollment_payload(false, false)$$,
    'Should accept default enrollment settings'
);

-- Should reject waitlists for approval-required events
select throws_ok(
    $$select validate_event_enrollment_payload(true, true)$$,
    'approval-required events cannot enable waitlist',
    'Should reject waitlists for approval-required events'
);

-- Should accept approval-required events without a waitlist
select lives_ok(
    $$select validate_event_enrollment_payload(true, false)$$,
    'Should accept approval-required events without a waitlist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
