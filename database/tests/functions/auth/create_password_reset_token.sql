-- Tests password reset token issuance, eligibility checks, and per-user cooldown.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userCooldownActiveID '0a120000-0000-0000-0000-000000000001'
\set userCooldownElapsedID '0a120000-0000-0000-0000-000000000002'
\set userEligibleID '0a120000-0000-0000-0000-000000000003'
\set userPreRegisteredID '0a120000-0000-0000-0000-000000000004'
\set userSsoOnlyID '0a120000-0000-0000-0000-000000000005'
\set userUnverifiedID '0a120000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Eligible user with a recently issued token inside the cooldown window
select fx_user(:'userCooldownActiveID', jsonb_build_object(
    'email', '0a12-cooldown-active@example.com',
    'email_verified', true,
    'password', 'hashed-password',
    'registration_status', 'registered'
));

-- Eligible user with an older token whose cooldown has elapsed
select fx_user(:'userCooldownElapsedID', jsonb_build_object(
    'email', '0a12-cooldown-elapsed@example.com',
    'email_verified', true,
    'password', 'hashed-password',
    'registration_status', 'registered'
));

-- Eligible verified password user with no existing token
select fx_user(:'userEligibleID', jsonb_build_object(
    'email', '0a12-eligible@example.com',
    'email_verified', true,
    'password', 'hashed-password',
    'registration_status', 'registered'
));

-- Pre-registered placeholder user ineligible for password reset
select fx_user(:'userPreRegisteredID', jsonb_build_object(
    'email', '0a12-preregistered@example.com',
    'email_verified', false,
    'password', null,
    'registration_status', 'pre-registered'
));

-- Verified SSO-only user without a password
select fx_user(:'userSsoOnlyID', jsonb_build_object(
    'email', '0a12-sso-only@example.com',
    'email_verified', true,
    'password', null,
    'registration_status', 'registered'
));

-- Unverified password user ineligible for password reset
select fx_user(:'userUnverifiedID', jsonb_build_object(
    'email', '0a12-unverified@example.com',
    'email_verified', false,
    'password', 'hashed-password',
    'registration_status', 'registered'
));

-- Recent token enforcing the 2-minute cooldown window
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a12-cooldown-active-initial', 'sha256'),
    current_timestamp - interval '1 minute',
    :'userCooldownActiveID'
);

-- Older token sitting at the 2-minute cooldown boundary
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a12-cooldown-elapsed-initial', 'sha256'),
    current_timestamp - interval '2 minutes',
    :'userCooldownElapsedID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a null template data payload
select throws_ok(
    $$select create_password_reset_token('0a12-eligible@example.com', digest('0a12-t0', 'sha256'), null)$$,
    'P0001',
    'password reset template data is required',
    'Should reject a null template data payload'
);

-- Should reject a null token hash
select throws_ok(
    $$select create_password_reset_token('0a12-eligible@example.com', null, '{"link":"https://example.test"}'::jsonb)$$,
    'P0001',
    'password reset token hash must be 32 bytes',
    'Should reject a null token hash'
);

-- Should reject a token hash that is not 32 bytes
select throws_ok(
    $$select create_password_reset_token('0a12-eligible@example.com', decode('deadbeef', 'hex'), '{"link":"https://example.test"}'::jsonb)$$,
    'P0001',
    'password reset token hash must be 32 bytes',
    'Should reject a token hash that is not 32 bytes'
);

-- Should silently ignore blank emails
select is(
    create_password_reset_token('   ', digest('0a12-blank', 'sha256'), '{"link":"https://example.test"}'::jsonb),
    false,
    'Should silently ignore blank emails'
);

-- Should silently ignore unknown emails
select is(
    create_password_reset_token('0a12-missing@example.com', digest('0a12-missing', 'sha256'), '{"link":"https://example.test"}'::jsonb),
    false,
    'Should silently ignore unknown emails'
);

-- Should silently ignore pre-registered users
select is(
    create_password_reset_token('0a12-preregistered@example.com', digest('0a12-prereg', 'sha256'), '{"link":"https://example.test"}'::jsonb),
    false,
    'Should silently ignore pre-registered users'
);

-- Should silently ignore SSO-only users without a password
select is(
    create_password_reset_token('0a12-sso-only@example.com', digest('0a12-sso', 'sha256'), '{"link":"https://example.test"}'::jsonb),
    false,
    'Should silently ignore SSO-only users without a password'
);

-- Should silently ignore unverified users
select is(
    create_password_reset_token('0a12-unverified@example.com', digest('0a12-unverified', 'sha256'), '{"link":"https://example.test"}'::jsonb),
    false,
    'Should silently ignore unverified users'
);

-- Should not write tokens or notifications for ineligible users
select is(
    (
        select count(*)::int
        from password_reset_token
        where user_id in (:'userPreRegisteredID'::uuid, :'userSsoOnlyID'::uuid, :'userUnverifiedID'::uuid)
    ),
    0,
    'Should not store tokens for ineligible users'
);
select is(
    (
        select count(*)::int
        from notification
        where user_id in (:'userPreRegisteredID'::uuid, :'userSsoOnlyID'::uuid, :'userUnverifiedID'::uuid)
    ),
    0,
    'Should not enqueue notifications for ineligible users'
);

-- Should enforce the 2-minute per-user cooldown and preserve the existing token
select is(
    create_password_reset_token(
        '0a12-cooldown-active@example.com',
        digest('0a12-cooldown-active-replacement', 'sha256'),
        '{"link":"https://example.test/replacement"}'::jsonb
    ),
    false,
    'Should suppress token issuance during the 2-minute cooldown'
);
select is(
    (select token_hash from password_reset_token where user_id = :'userCooldownActiveID'::uuid),
    digest('0a12-cooldown-active-initial', 'sha256'),
    'Should keep the existing token hash intact during cooldown'
);
select is(
    (select count(*)::int from notification where user_id = :'userCooldownActiveID'::uuid),
    0,
    'Should not enqueue a notification during cooldown'
);

-- Should replace an older token once the 2-minute cooldown elapses
select is(
    create_password_reset_token(
        '0a12-cooldown-elapsed@example.com',
        digest('0a12-cooldown-elapsed-new', 'sha256'),
        '{"link":"https://example.test/elapsed"}'::jsonb
    ),
    true,
    'Should issue a replacement token once cooldown elapses'
);
select is(
    (select token_hash from password_reset_token where user_id = :'userCooldownElapsedID'::uuid),
    digest('0a12-cooldown-elapsed-new', 'sha256'),
    'Should replace the stored token hash after cooldown'
);

-- Should match emails case-insensitively with whitespace, store the token, and enqueue a notification
select is(
    create_password_reset_token(
        '  0A12-ELIGIBLE@EXAMPLE.COM  ',
        digest('0a12-eligible-token', 'sha256'),
        '{"link":"https://example.test/reset-password/eligible"}'::jsonb
    ),
    true,
    'Should issue a password reset token for an eligible user'
);
select is(
    (select token_hash from password_reset_token where user_id = :'userEligibleID'::uuid),
    digest('0a12-eligible-token', 'sha256'),
    'Should persist the SHA-256 token hash for the eligible user'
);
select results_eq(
    format(
        $$
            select n.kind, ntd.data
            from notification n
            join notification_template_data ntd using (notification_template_data_id)
            where n.user_id = %L::uuid
        $$,
        :'userEligibleID'
    ),
    $$
        values (
            'password-reset',
            '{"link":"https://example.test/reset-password/eligible"}'::jsonb
        )
    $$,
    'Should enqueue the password-reset notification with its template data'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
