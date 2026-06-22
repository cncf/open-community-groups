-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userNoPasswordID '0a070000-0000-0000-0000-000000000001'
\set userPreRegisteredID '0a070000-0000-0000-0000-000000000002'
\set userUnverifiedID '0a070000-0000-0000-0000-000000000003'
\set userWithPasswordID '0a070000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    password,
    registration_status,
    username
) values (
    :'userNoPasswordID',
    'no-password-hash',
    'no-password@example.com',
    true,
    null,
    'registered',
    'no-password'
), (
    :'userPreRegisteredID',
    'pre-registered-hash',
    'pre-registered@example.com',
    true,
    'hidden-password',
    'pre-registered',
    'pre-registered-user'
), (
    :'userUnverifiedID',
    'unverified-hash',
    'unverified@example.com',
    false,
    'hidden-password',
    'registered',
    'unverified-user'
), (
    :'userWithPasswordID',
    'password-hash',
    'with-password@example.com',
    true,
    'password_value',
    'registered',
    'with-password'
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

-- Should return verified user with password by username ignoring case
select is(
    get_user_by_username('WITH-PASSWORD')::jsonb->>'user_id',
    :'userWithPasswordID',
    'Should return verified user with password by username ignoring case'
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

-- Should return null for pre-registered user
select is(
    get_user_by_username('pre-registered-user')::jsonb,
    null::jsonb,
    'Should return null for pre-registered user'
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
