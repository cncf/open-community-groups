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

-- Pre-registered user returned before email verification
select fx_user(:'userPreRegisteredID', jsonb_build_object(
    'email', 'invited-external-auth@example.com',
    'email_verified', false,
    'registration_status', 'pre-registered'
));

-- Registered user returned by external auth email lookup
select fx_user(:'userRegisteredID', jsonb_build_object('email', 'registered-external-auth@example.com'));

-- Unverified registered user excluded from external auth lookup
select fx_user(:'userUnverifiedID', jsonb_build_object(
    'email', 'unverified-external-auth@example.com',
    'email_verified', false
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return verified registered users for external auth.
select is(
    get_user_by_email_for_external_auth('REGISTERED-EXTERNAL-AUTH@example.com')::jsonb->>'registration_status',
    'registered',
    'Should return verified registered users case-insensitively'
);

-- Should not include password in external auth lookup.
select is(
    get_user_by_email_for_external_auth('registered-external-auth@example.com')::jsonb ? 'password',
    false,
    'Should not include password in external auth lookup'
);

-- Should not return unverified registered users.
select is(
    get_user_by_email_for_external_auth('unverified-external-auth@example.com')::jsonb,
    null::jsonb,
    'Should not return unverified registered users'
);

-- Should return pre-registered users before email verification.
select is(
    get_user_by_email_for_external_auth('invited-external-auth@example.com')::jsonb->>'registration_status',
    'pre-registered',
    'Should return pre-registered users before email verification'
);

-- Should include required user fields for pre-registered placeholders.
select is(
    get_user_by_email_for_external_auth('invited-external-auth@example.com')::jsonb->>'name',
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
