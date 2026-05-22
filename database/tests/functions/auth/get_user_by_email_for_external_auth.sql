-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userPreRegisteredID '00000000-0000-0000-0000-000000000103'
\set userRegisteredID '00000000-0000-0000-0000-000000000101'
\set userUnverifiedID '00000000-0000-0000-0000-000000000102'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (
    auth_hash,
    email,
    email_verified,
    password,
    registration_status,
    user_id,
    username
) values
    ('registered-hash', 'registered@example.com', true, 'secret', 'registered', :'userRegisteredID', 'registered-user'),
    ('unverified-hash', 'unverified@example.com', false, null, 'registered', :'userUnverifiedID', 'unverified-user'),
    ('pre-registered-hash', 'invited@example.com', false, null, 'pre-registered', :'userPreRegisteredID', 'invited-user');

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
