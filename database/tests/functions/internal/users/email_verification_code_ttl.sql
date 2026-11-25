-- Tests email verification code validity window.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the shared email verification code validity window
select is(
    email_verification_code_ttl(),
    interval '1 day',
    'Should return the shared email verification code validity window'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
