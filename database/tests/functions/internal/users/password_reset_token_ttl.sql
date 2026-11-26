-- Tests password reset token validity window.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the shared password reset token validity window
select is(
    password_reset_token_ttl(),
    interval '1 hour',
    'Should return the shared password reset token validity window'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
