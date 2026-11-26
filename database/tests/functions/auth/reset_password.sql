-- Tests single-use password reset token consumption, password update, and auth_hash rotation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set notifValidID '0a160000-0000-0000-0000-000000000021'
\set tplValidID '0a160000-0000-0000-0000-000000000011'
\set userEligibleID '0a160000-0000-0000-0000-000000000001'
\set userExpiredID '0a160000-0000-0000-0000-000000000002'
\set userPreRegisteredID '0a160000-0000-0000-0000-000000000003'
\set userSsoOnlyID '0a160000-0000-0000-0000-000000000004'
\set userUntouchedID '0a160000-0000-0000-0000-000000000005'
\set userUnverifiedID '0a160000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Stored password-reset notification payload that must be scrubbed on consumption
insert into notification_template_data (notification_template_data_id, data, hash)
values (
    :'tplValidID',
    '{"link":"https://example.test/reset-password/0a16-valid"}'::jsonb,
    encode(digest('0a16-valid-payload', 'sha256'), 'hex')
);

-- Eligible verified password user resetting their password
select fx_user(:'userEligibleID', jsonb_build_object(
    'auth_hash', '0a16_initial_auth_hash',
    'email_verified', true,
    'password', '0a16_old_password_hash',
    'registration_status', 'registered',
    'username', '0a16-reset-target'
));

-- Eligible user holding an expired reset token
select fx_user(:'userExpiredID', jsonb_build_object(
    'email_verified', true,
    'password', '0a16_expired_password_hash',
    'registration_status', 'registered'
));

-- Pre-registered user holding a reset token
select fx_user(:'userPreRegisteredID', jsonb_build_object(
    'email_verified', false,
    'password', null,
    'registration_status', 'pre-registered'
));

-- SSO-only user without a password holding a reset token
select fx_user(:'userSsoOnlyID', jsonb_build_object(
    'email_verified', true,
    'password', null,
    'registration_status', 'registered'
));

-- Control user whose credentials remain untouched
select fx_user(:'userUntouchedID', jsonb_build_object(
    'auth_hash', '0a16_control_auth_hash',
    'email_verified', true,
    'password', '0a16_control_password_hash',
    'registration_status', 'registered'
));

-- Unverified user holding a reset token
select fx_user(:'userUnverifiedID', jsonb_build_object(
    'email_verified', false,
    'password', '0a16_unverified_password_hash',
    'registration_status', 'registered'
));

-- Pending password-reset notification linked to the eligible user
insert into notification (notification_id, delivery_status, kind, notification_template_data_id, user_id)
values (:'notifValidID', 'pending', 'password-reset', :'tplValidID', :'userEligibleID');

-- Valid reset token within the 1-hour validity window
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a16-valid', 'sha256'),
    current_timestamp - interval '30 minutes',
    :'userEligibleID'
);

-- Expired reset token sitting on the 1-hour validity boundary
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a16-expired', 'sha256'),
    current_timestamp - interval '1 hour',
    :'userExpiredID'
);

-- Token owned by a pre-registered user
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a16-prereg', 'sha256'),
    current_timestamp - interval '5 minutes',
    :'userPreRegisteredID'
);

-- Token owned by an SSO-only user
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a16-sso', 'sha256'),
    current_timestamp - interval '5 minutes',
    :'userSsoOnlyID'
);

-- Token owned by an unverified user
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a16-unverified', 'sha256'),
    current_timestamp - interval '5 minutes',
    :'userUnverifiedID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a blank password hash
select throws_ok(
    $$select reset_password(digest('0a16-valid', 'sha256'), '   ')$$,
    'P0001',
    'password hash is required',
    'Should reject a blank password hash'
);

-- Should reject a null password hash
select throws_ok(
    $$select reset_password(digest('0a16-valid', 'sha256'), null)$$,
    'P0001',
    'password hash is required',
    'Should reject a null password hash'
);

-- Should reject a null token hash
select throws_ok(
    $$select reset_password(null, '0a16_new_password_hash')$$,
    'P0001',
    'password reset token hash must be 32 bytes',
    'Should reject a null token hash'
);

-- Should reject a token hash that is not 32 bytes
select throws_ok(
    $$select reset_password(decode('deadbeef', 'hex'), '0a16_new_password_hash')$$,
    'P0001',
    'password reset token hash must be 32 bytes',
    'Should reject a token hash that is not 32 bytes'
);

-- Should reject an unknown token
select throws_ok(
    $$select reset_password(digest('0a16-missing', 'sha256'), '0a16_new_password_hash')$$,
    'OCG01',
    'password reset failed: invalid or expired token',
    'Should reject an unknown token'
);

-- Should reject an expired token
select throws_ok(
    $$select reset_password(digest('0a16-expired', 'sha256'), '0a16_new_password_hash')$$,
    'OCG01',
    'password reset failed: invalid or expired token',
    'Should reject an expired token'
);

-- Should reject a token owned by a pre-registered user
select throws_ok(
    $$select reset_password(digest('0a16-prereg', 'sha256'), '0a16_new_password_hash')$$,
    'OCG01',
    'password reset failed: invalid or expired token',
    'Should reject a token owned by a pre-registered user'
);

-- Should reject a token owned by an SSO-only user
select throws_ok(
    $$select reset_password(digest('0a16-sso', 'sha256'), '0a16_new_password_hash')$$,
    'OCG01',
    'password reset failed: invalid or expired token',
    'Should reject a token owned by an SSO-only user'
);

-- Should reject a token owned by an unverified user
select throws_ok(
    $$select reset_password(digest('0a16-unverified', 'sha256'), '0a16_new_password_hash')$$,
    'OCG01',
    'password reset failed: invalid or expired token',
    'Should reject a token owned by an unverified user'
);

-- Should consume a valid token, update password, rotate auth_hash, scrub payload, and write an audit row
select lives_ok(
    $$select reset_password(digest('0a16-valid', 'sha256'), '0a16_new_password_hash')$$,
    'Should reset password with a valid token'
);
select is(
    (select count(*)::int from password_reset_token where user_id = :'userEligibleID'::uuid),
    0,
    'Should delete the password reset token after consumption'
);
select is(
    (
        select count(*)::int
        from notification_template_data
        where notification_template_data_id = :'tplValidID'::uuid
    ),
    0,
    'Should scrub stored password-reset notification template data after consumption'
);
select is(
    (select password from "user" where user_id = :'userEligibleID'::uuid),
    '0a16_new_password_hash',
    'Should update the user password hash'
);
select isnt(
    (select auth_hash from "user" where user_id = :'userEligibleID'::uuid),
    '0a16_initial_auth_hash',
    'Should rotate auth_hash to invalidate existing sessions'
);
select results_eq(
    format(
        $$
            select
                action,
                actor_user_id,
                actor_username,
                details,
                resource_id,
                resource_type
            from audit_log
            where resource_id = %L::uuid
        $$,
        :'userEligibleID'
    ),
    format(
        $$
            values (
                'user_password_updated',
                %L::uuid,
                '0a16-reset-target',
                '{"via":"password_reset"}'::jsonb,
                %L::uuid,
                'user'
            )
        $$,
        :'userEligibleID',
        :'userEligibleID'
    ),
    'Should record the password reset in audit_log'
);

-- Should reject replaying a consumed token
select throws_ok(
    $$select reset_password(digest('0a16-valid', 'sha256'), '0a16_replayed_password_hash')$$,
    'OCG01',
    'password reset failed: invalid or expired token',
    'Should reject replaying a consumed token'
);

-- Should not modify other users
select results_eq(
    format(
        $$select auth_hash, password from "user" where user_id = %L::uuid$$,
        :'userUntouchedID'
    ),
    $$values ('0a16_control_auth_hash', '0a16_control_password_hash')$$,
    'Should not modify other users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
