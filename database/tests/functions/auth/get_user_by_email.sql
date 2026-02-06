-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userUnverifiedID '00000000-0000-0000-0000-000000000101'
\set userVerifiedID '00000000-0000-0000-0000-000000000102'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Verified user
insert into "user" (auth_hash, email, email_verified, user_id, username) values (
    'verified_hash',
    'verified@example.com',
    true,
    :'userVerifiedID',
    'verified-user'
);

-- Unverified user
insert into "user" (auth_hash, email, email_verified, user_id, username) values (
    'unverified_hash',
    'unverified@example.com',
    false,
    :'userUnverifiedID',
    'unverified-user'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return verified user by email
select is(
    get_user_by_email('verified@example.com')::jsonb->>'email',
    'verified@example.com',
    'Should return verified user by email'
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
