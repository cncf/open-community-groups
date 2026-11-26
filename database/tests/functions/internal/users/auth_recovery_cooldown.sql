-- Tests the shared per-user cooldown window for auth recovery emails.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the shared auth recovery cooldown window
select is(
    auth_recovery_cooldown(),
    interval '2 minutes',
    'Should return the shared auth recovery cooldown window'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
