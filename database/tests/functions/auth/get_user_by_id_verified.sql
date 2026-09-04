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

-- Pre-registered user excluded from verified lookup
select fx_user(:'userPreRegisteredID', jsonb_build_object('registration_status', 'pre-registered'));

-- Unverified registered user excluded from verified lookup
select fx_user(:'userUnverifiedID', jsonb_build_object('email_verified', false));

-- Verified registered user returned by identifier
select fx_user(:'userVerifiedID');

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
