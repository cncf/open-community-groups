-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userUnverifiedID '0a030000-0000-0000-0000-000000000001'
\set userVerifiedID '0a030000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Verified user matched by email
select fx_user(:'userVerifiedID', jsonb_build_object('email', 'verified@example.com'));

-- Unverified user excluded from email lookup
select fx_user(:'userUnverifiedID', jsonb_build_object(
    'email', 'unverified@example.com',
    'email_verified', false
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return verified user by email
select is(
    get_user_by_email('verified@example.com')::jsonb->>'email',
    'verified@example.com',
    'Should return verified user by email'
);

-- Should return verified user by email ignoring case
select is(
    get_user_by_email('VERIFIED@EXAMPLE.COM')::jsonb->>'email',
    'verified@example.com',
    'Should return verified user by email ignoring case'
);

-- Should not include password for email lookup
select is(
    (get_user_by_email('verified@example.com')::jsonb ? 'password'),
    false,
    'Should not include password for email lookup'
);

-- Should return null for unverified email
select is(
    get_user_by_email('unverified@example.com')::jsonb,
    null::jsonb,
    'Should return null for unverified email'
);

-- Should return null when email does not exist
select is(
    get_user_by_email('missing@example.com')::jsonb,
    null::jsonb,
    'Should return null when email does not exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
