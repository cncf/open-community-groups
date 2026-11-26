-- Tests resending email verification codes with eligibility and cooldown rules.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set codeCooldownActiveInitialID '0a150000-0000-0000-0000-000000000011'
\set codeCooldownActiveNewID '0a150000-0000-0000-0000-000000000012'
\set codeCooldownElapsedInitialID '0a150000-0000-0000-0000-000000000013'
\set codeCooldownElapsedNewID '0a150000-0000-0000-0000-000000000014'
\set codeNoExistingNewID '0a150000-0000-0000-0000-000000000015'
\set codeUnusedID '0a150000-0000-0000-0000-000000000016'
\set notifSupersededPendingID '0a150000-0000-0000-0000-000000000021'
\set userCooldownActiveID '0a150000-0000-0000-0000-000000000001'
\set userCooldownElapsedID '0a150000-0000-0000-0000-000000000002'
\set userNoCodeID '0a150000-0000-0000-0000-000000000003'
\set userPreRegisteredID '0a150000-0000-0000-0000-000000000004'
\set userVerifiedID '0a150000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Unverified registered user with a verification code still inside cooldown
select fx_user(:'userCooldownActiveID', jsonb_build_object(
    'email', '0a15-cooldown-active@example.com',
    'email_verified', false,
    'password', 'hashed-password',
    'registration_status', 'registered'
));

-- Unverified registered user whose verification code cooldown has elapsed
select fx_user(:'userCooldownElapsedID', jsonb_build_object(
    'email', '0a15-cooldown-elapsed@example.com',
    'email_verified', false,
    'password', 'hashed-password',
    'registration_status', 'registered'
));

-- Unverified registered user whose prior code was already cleaned up
select fx_user(:'userNoCodeID', jsonb_build_object(
    'email', '0a15-no-code@example.com',
    'email_verified', false,
    'password', 'hashed-password',
    'registration_status', 'registered'
));

-- Pre-registered placeholder user ineligible for verification resend
select fx_user(:'userPreRegisteredID', jsonb_build_object(
    'email', '0a15-preregistered@example.com',
    'email_verified', false,
    'password', null,
    'registration_status', 'pre-registered'
));

-- Verified registered user ineligible for verification resend
select fx_user(:'userVerifiedID', jsonb_build_object(
    'email', '0a15-verified@example.com',
    'email_verified', true,
    'password', 'hashed-password',
    'registration_status', 'registered'
));

-- Recent verification code enforcing the 2-minute cooldown window
insert into email_verification_code (email_verification_code_id, created_at, user_id)
values (
    :'codeCooldownActiveInitialID',
    current_timestamp - interval '1 minute',
    :'userCooldownActiveID'
);

-- Older verification code sitting at the 2-minute cooldown boundary
insert into email_verification_code (email_verification_code_id, created_at, user_id)
values (
    :'codeCooldownElapsedInitialID',
    current_timestamp - interval '2 minutes',
    :'userCooldownElapsedID'
);

-- Pending verification email that must be canceled when superseded by resend
insert into notification (notification_id, delivery_status, kind, user_id)
values (:'notifSupersededPendingID', 'pending', 'email-verification', :'userCooldownElapsedID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a null template data payload
select throws_ok(
    format(
        $$select resend_email_verification('0a15-no-code@example.com', %L::uuid, null)$$,
        :'codeUnusedID'
    ),
    'P0001',
    'verification template data is required to send verification email',
    'Should reject a null template data payload'
);

-- Should reject a null verification code
select throws_ok(
    $$select resend_email_verification('0a15-no-code@example.com', null, '{"link":"https://example.test"}'::jsonb)$$,
    'P0001',
    'verification code is required to send verification email',
    'Should reject a null verification code'
);

-- Should silently ignore blank emails
select is(
    resend_email_verification('   ', :'codeUnusedID'::uuid, '{"link":"https://example.test"}'::jsonb),
    false,
    'Should silently ignore blank emails'
);

-- Should silently ignore unknown emails
select is(
    resend_email_verification('0a15-missing@example.com', :'codeUnusedID'::uuid, '{"link":"https://example.test"}'::jsonb),
    false,
    'Should silently ignore unknown emails'
);

-- Should silently ignore pre-registered users
select is(
    resend_email_verification('0a15-preregistered@example.com', :'codeUnusedID'::uuid, '{"link":"https://example.test"}'::jsonb),
    false,
    'Should silently ignore pre-registered users'
);

-- Should silently ignore already verified users
select is(
    resend_email_verification('0a15-verified@example.com', :'codeUnusedID'::uuid, '{"link":"https://example.test"}'::jsonb),
    false,
    'Should silently ignore already verified users'
);

-- Should not create codes or notifications for ineligible users
select is(
    (
        select count(*)::int
        from email_verification_code
        where user_id in (:'userPreRegisteredID'::uuid, :'userVerifiedID'::uuid)
    ),
    0,
    'Should not store codes for ineligible users'
);
select is(
    (
        select count(*)::int
        from notification
        where user_id in (:'userPreRegisteredID'::uuid, :'userVerifiedID'::uuid)
    ),
    0,
    'Should not enqueue notifications for ineligible users'
);

-- Should enforce the 2-minute per-user cooldown and preserve the active code
select is(
    resend_email_verification(
        '0a15-cooldown-active@example.com',
        :'codeCooldownActiveNewID'::uuid,
        '{"link":"https://example.test/blocked"}'::jsonb
    ),
    false,
    'Should suppress verification resend during the 2-minute cooldown'
);
select is(
    (select email_verification_code_id from email_verification_code where user_id = :'userCooldownActiveID'::uuid),
    :'codeCooldownActiveInitialID'::uuid,
    'Should keep the existing verification code intact during cooldown'
);
select is(
    (select count(*)::int from notification where user_id = :'userCooldownActiveID'::uuid),
    0,
    'Should not enqueue a notification during cooldown'
);

-- Should replace an older verification code once cooldown elapses
select is(
    resend_email_verification(
        '0a15-cooldown-elapsed@example.com',
        :'codeCooldownElapsedNewID'::uuid,
        '{"link":"https://example.test/resent"}'::jsonb
    ),
    true,
    'Should issue a new verification code once cooldown elapses'
);
select is(
    (select email_verification_code_id from email_verification_code where user_id = :'userCooldownElapsedID'::uuid),
    :'codeCooldownElapsedNewID'::uuid,
    'Should replace the verification code after cooldown'
);
select results_eq(
    format(
        $$
            select n.kind, ntd.data
            from notification n
            join notification_template_data ntd using (notification_template_data_id)
            where n.user_id = %L::uuid
        $$,
        :'userCooldownElapsedID'
    ),
    $$
        values (
            'email-verification',
            '{"link":"https://example.test/resent"}'::jsonb
        )
    $$,
    'Should enqueue the email-verification notification after cooldown'
);
select results_eq(
    format(
        $$
            select delivery_status, error
            from notification
            where notification_id = %L::uuid
        $$,
        :'notifSupersededPendingID'
    ),
    $$values ('failed'::text, 'email verification code superseded'::text)$$,
    'Should cancel superseded pending email-verification notifications on resend'
);

-- Should issue a verification code when an unverified user has no existing code
select is(
    resend_email_verification(
        '  0A15-NO-CODE@EXAMPLE.COM  ',
        :'codeNoExistingNewID'::uuid,
        '{"link":"https://example.test/fresh"}'::jsonb
    ),
    true,
    'Should issue a verification code when no existing code is present'
);
select is(
    (select email_verification_code_id from email_verification_code where user_id = :'userNoCodeID'::uuid),
    :'codeNoExistingNewID'::uuid,
    'Should store the new verification code for the user without a prior code'
);
select is(
    (select count(*)::int from notification where user_id = :'userNoCodeID'::uuid and kind = 'email-verification'),
    1,
    'Should enqueue one email-verification notification for the user without a prior code'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
