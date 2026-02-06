-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userNoPasswordID '00000000-0000-0000-0000-000000000121'
\set userUnverifiedID '00000000-0000-0000-0000-000000000122'
\set userWithPasswordID '00000000-0000-0000-0000-000000000123'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Verified user with password
insert into "user" (
    auth_hash,
    email,
    email_verified,
    password,
    user_id,
    username
) values (
    'password_hash',
    'with-password@example.com',
    true,
    'password_value',
    :'userWithPasswordID',
    'with-password'
);

-- Verified user without password
insert into "user" (
    auth_hash,
    email,
    email_verified,
    user_id,
    username
) values (
    'no_password_hash',
    'no-password@example.com',
    true,
    :'userNoPasswordID',
    'no-password'
);

-- Unverified user with password
insert into "user" (
    auth_hash,
    email,
    email_verified,
    password,
    user_id,
    username
) values (
    'unverified_hash',
    'unverified@example.com',
    false,
    'hidden_password',
    :'userUnverifiedID',
    'unverified-user'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return verified user with password by username
select is(
    get_user_by_username('with-password')::jsonb->>'user_id',
    :'userWithPasswordID',
    'Should return verified user with password by username'
);

-- Should include password for username lookup
select is(
    get_user_by_username('with-password')::jsonb->>'password',
    'password_value',
    'Should include password for username lookup'
);

-- Should return null when verified user has no password
select is(
    get_user_by_username('no-password')::jsonb,
    null::jsonb,
    'Should return null when verified user has no password'
);

-- Should return null for unverified user
select is(
    get_user_by_username('unverified-user')::jsonb,
    null::jsonb,
    'Should return null for unverified user'
);

-- Should return null when username does not exist
select is(
    get_user_by_username('missing-user')::jsonb,
    null::jsonb,
    'Should return null when username does not exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
