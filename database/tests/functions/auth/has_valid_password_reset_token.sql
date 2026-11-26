-- Tests password reset token validity checks.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userEligibleID '0a140000-0000-0000-0000-000000000001'
\set userExpiredID '0a140000-0000-0000-0000-000000000002'
\set userPreRegisteredID '0a140000-0000-0000-0000-000000000003'
\set userSsoOnlyID '0a140000-0000-0000-0000-000000000004'
\set userUnverifiedID '0a140000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Eligible verified password user with an active token
select fx_user(:'userEligibleID', jsonb_build_object(
    'email_verified', true,
    'password', 'hashed-password',
    'registration_status', 'registered'
));

-- Eligible verified password user with an expired token
select fx_user(:'userExpiredID', jsonb_build_object(
    'email_verified', true,
    'password', 'hashed-password',
    'registration_status', 'registered'
));

-- Pre-registered user holding a token
select fx_user(:'userPreRegisteredID', jsonb_build_object(
    'email_verified', false,
    'password', null,
    'registration_status', 'pre-registered'
));

-- SSO-only user without a password holding a token
select fx_user(:'userSsoOnlyID', jsonb_build_object(
    'email_verified', true,
    'password', null,
    'registration_status', 'registered'
));

-- Unverified user holding a token
select fx_user(:'userUnverifiedID', jsonb_build_object(
    'email_verified', false,
    'password', 'hashed-password',
    'registration_status', 'registered'
));

-- Active token within the 1-hour validity window
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a14-valid', 'sha256'),
    current_timestamp - interval '30 minutes',
    :'userEligibleID'
);

-- Expired token sitting on the 1-hour validity boundary
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a14-expired', 'sha256'),
    current_timestamp - interval '1 hour',
    :'userExpiredID'
);

-- Token owned by a pre-registered user
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a14-prereg', 'sha256'),
    current_timestamp - interval '5 minutes',
    :'userPreRegisteredID'
);

-- Token owned by an SSO-only user
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a14-sso', 'sha256'),
    current_timestamp - interval '5 minutes',
    :'userSsoOnlyID'
);

-- Token owned by an unverified user
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a14-unverified', 'sha256'),
    current_timestamp - interval '5 minutes',
    :'userUnverifiedID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return false for an expired token
select is(
    has_valid_password_reset_token(digest('0a14-expired', 'sha256')),
    false,
    'Should return false for an expired token'
);

-- Should return false for a missing token
select is(
    has_valid_password_reset_token(digest('0a14-missing', 'sha256')),
    false,
    'Should return false for a missing token'
);

-- Should return false for a token owned by a pre-registered user
select is(
    has_valid_password_reset_token(digest('0a14-prereg', 'sha256')),
    false,
    'Should return false for a token owned by a pre-registered user'
);

-- Should return false for a token owned by an SSO-only user
select is(
    has_valid_password_reset_token(digest('0a14-sso', 'sha256')),
    false,
    'Should return false for a token owned by an SSO-only user'
);

-- Should return false for a token owned by an unverified user
select is(
    has_valid_password_reset_token(digest('0a14-unverified', 'sha256')),
    false,
    'Should return false for a token owned by an unverified user'
);

-- Should return true for an active token owned by an eligible user
select is(
    has_valid_password_reset_token(digest('0a14-valid', 'sha256')),
    true,
    'Should return true for an active token owned by an eligible user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
