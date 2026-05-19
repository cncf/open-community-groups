-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set nonExistentUserID '00000000-0000-0000-0000-000000009999'
\set userPreRegisteredID '00000000-0000-0000-0000-000000000113'
\set userUnverifiedID '00000000-0000-0000-0000-000000000111'
\set userVerifiedID '00000000-0000-0000-0000-000000000112'

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

-- Pre-registered user
insert into "user" (auth_hash, email, email_verified, registration_status, user_id, username) values (
    'pre_registered_hash',
    'pre-registered@example.com',
    true,
    'pre-registered',
    :'userPreRegisteredID',
    'pre-registered-user'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return verified user by ID
select is(
    get_user_by_id_verified(:'userVerifiedID'::uuid)::jsonb->>'user_id',
    :'userVerifiedID',
    'Should return verified user by ID'
);

-- Should return null for unverified user
select is(
    get_user_by_id_verified(:'userUnverifiedID'::uuid)::jsonb,
    null::jsonb,
    'Should return null for unverified user'
);

-- Should return null for pre-registered user
select is(
    get_user_by_id_verified(:'userPreRegisteredID'::uuid)::jsonb,
    null::jsonb,
    'Should return null for pre-registered user'
);

-- Should return null when user does not exist
select is(
    get_user_by_id_verified(:'nonExistentUserID'::uuid)::jsonb,
    null::jsonb,
    'Should return null when user does not exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
