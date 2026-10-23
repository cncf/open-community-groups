-- Tests projecting users for external authentication.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set namelessUserID 'f7a20000-0000-0000-0000-000000000001'
\set preRegisteredUserID 'f7a20000-0000-0000-0000-000000000002'
\set registeredUserID 'f7a20000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Registered user without a name
select fx_user(:'namelessUserID', jsonb_build_object(
    'name', null,
    'registration_status', 'registered'
));

-- Pre-registered placeholder user
select fx_user(:'preRegisteredUserID', jsonb_build_object(
    'email_verified', false,
    'name', 'Pre-registered User',
    'registration_status', 'pre-registered'
));

-- Registered user with a password hash that must not be returned
select fx_user(:'registeredUserID', jsonb_build_object(
    'auth_hash', 'external-auth-user-json-hash',
    'email', 'external-auth-user-json@example.com',
    'email_verified', true,
    'name', 'Registered User',
    'password', 'external-auth-user-json-password',
    'registration_status', 'registered',
    'username', 'external-auth-user-json'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should coalesce a missing name to an empty string
select is(
    (select external_auth_user_json(u)::jsonb->>'name' from "user" u where u.user_id = :'namelessUserID'),
    '',
    'Should coalesce a missing name to an empty string'
);

-- Should include the registration status of pre-registered users
select is(
    (
        select external_auth_user_json(u)::jsonb->>'registration_status'
        from "user" u
        where u.user_id = :'preRegisteredUserID'
    ),
    'pre-registered',
    'Should include the registration status of pre-registered users'
);

-- Should return the user projection with the registration status and no password
select is(
    (select external_auth_user_json(u)::jsonb from "user" u where u.user_id = :'registeredUserID'),
    jsonb_build_object(
        'auth_hash', 'external-auth-user-json-hash',
        'email', 'external-auth-user-json@example.com',
        'email_verified', true,
        'name', 'Registered User',
        'registration_status', 'registered',
        'user_id', :'registeredUserID',
        'username', 'external-auth-user-json',

        'has_password', true,

        'belongs_to_any_group_team', false,
        'belongs_to_community_team', false
    ),
    'Should return the user projection with the registration status and no password'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
