-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set nonExistentUserID '0a060000-0000-0000-0000-000000000001'
\set userPreRegisteredID '0a060000-0000-0000-0000-000000000002'
\set userUnverifiedID '0a060000-0000-0000-0000-000000000003'
\set userVerifiedID '0a060000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    registration_status,
    username
) values (
    :'userPreRegisteredID',
    'pre-registered-hash',
    'pre-registered@example.com',
    true,
    'pre-registered',
    'pre-registered-user'
), (
    :'userUnverifiedID',
    'unverified-hash',
    'unverified@example.com',
    false,
    'registered',
    'unverified-user'
), (
    :'userVerifiedID',
    'verified-hash',
    'verified@example.com',
    true,
    'registered',
    'verified-user'
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
