-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userPreRegisteredID '0a040000-0000-0000-0000-000000000001'
\set userRegisteredID '0a040000-0000-0000-0000-000000000002'
\set userUnverifiedID '0a040000-0000-0000-0000-000000000003'

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
    :'userPreRegisteredID',
    'pre-registered-hash',
    'invited@example.com',
    false,
    null,
    'pre-registered',
    'invited-user'
), (
    :'userRegisteredID',
    'registered-hash',
    'registered@example.com',
    true,
    'registered-password',
    'registered',
    'registered-user'
), (
    :'userUnverifiedID',
    'unverified-hash',
    'unverified@example.com',
    false,
    null,
    'registered',
    'unverified-user'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return verified registered users for external auth.
select is(
    get_user_by_email_for_external_auth('REGISTERED@example.com')::jsonb->>'registration_status',
    'registered',
    'Should return verified registered users case-insensitively'
);

-- Should not include password in external auth lookup.
select is(
    get_user_by_email_for_external_auth('registered@example.com')::jsonb ? 'password',
    false,
    'Should not include password in external auth lookup'
);

-- Should not return unverified registered users.
select is(
    get_user_by_email_for_external_auth('unverified@example.com')::jsonb,
    null::jsonb,
    'Should not return unverified registered users'
);

-- Should return pre-registered users before email verification.
select is(
    get_user_by_email_for_external_auth('invited@example.com')::jsonb->>'registration_status',
    'pre-registered',
    'Should return pre-registered users before email verification'
);

-- Should include required user fields for pre-registered placeholders.
select is(
    get_user_by_email_for_external_auth('invited@example.com')::jsonb->>'name',
    '',
    'Should include required user fields for pre-registered placeholders'
);

-- Should return null when the email does not exist.
select is(
    get_user_by_email_for_external_auth('missing@example.com')::jsonb,
    null::jsonb,
    'Should return null when the email does not exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
