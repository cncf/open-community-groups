-- Tests storing email verification codes and queueing the verification email.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set insertedCodeID 'f7a10000-0000-0000-0000-000000000002'
\set previousCodeID 'f7a10000-0000-0000-0000-000000000004'
\set rotatedCodeID 'f7a10000-0000-0000-0000-000000000005'
\set userWithCodeID 'f7a10000-0000-0000-0000-000000000003'
\set userWithoutCodeID 'f7a10000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Unverified user holding a previous verification code
select fx_user(:'userWithCodeID', jsonb_build_object('email_verified', false));

-- Unverified user without a verification code
select fx_user(:'userWithoutCodeID', jsonb_build_object('email_verified', false));

-- Previous verification code replaced by the rotation scenario
insert into email_verification_code (email_verification_code_id, user_id, created_at)
values (:'previousCodeID', :'userWithCodeID', '2024-01-01 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the caller-provided code for a user without one
select is(
    issue_email_verification(
        :'userWithoutCodeID',
        :'insertedCodeID',
        jsonb_build_object(
            'link', 'https://example.test/verify-email/' || :'insertedCodeID',
            'theme', jsonb_build_object('primary_color', '#123456')
        )
    ),
    :'insertedCodeID'::uuid,
    'Should return the caller-provided code for a user without one'
);

-- Should store the caller-provided code for a user without one
select results_eq(
    format(
        $$
            select email_verification_code_id
            from email_verification_code
            where user_id = %L::uuid
        $$,
        :'userWithoutCodeID'
    ),
    format($$values (%L::uuid)$$, :'insertedCodeID'),
    'Should store the caller-provided code for a user without one'
);

-- Should queue the email verification notification with the template data
select results_eq(
    format(
        $$
            select ntd.data
            from notification n
            join notification_template_data ntd using (notification_template_data_id)
            where n.kind = 'email-verification'
            and n.user_id = %L::uuid
        $$,
        :'userWithoutCodeID'
    ),
    format(
        $$values (%L::jsonb)$$,
        jsonb_build_object(
            'link', 'https://example.test/verify-email/' || :'insertedCodeID',
            'theme', jsonb_build_object('primary_color', '#123456')
        )
    ),
    'Should queue the email verification notification with the template data'
);

-- Should reject a missing verification code
select throws_ok(
    format(
        $$select issue_email_verification(%L::uuid, null::uuid, '{}'::jsonb)$$,
        :'userWithoutCodeID'
    ),
    'P0001',
    'verification code is required to send verification email',
    'Should reject a missing verification code'
);

-- Should reject missing verification template data
select throws_ok(
    format(
        $$select issue_email_verification(%L::uuid, %L::uuid, null::jsonb)$$,
        :'userWithoutCodeID',
        :'insertedCodeID'
    ),
    'P0001',
    'verification template data is required to send verification email',
    'Should reject missing verification template data'
);

-- Should return the caller-provided code when rotating an existing one
select is(
    issue_email_verification(:'userWithCodeID', :'rotatedCodeID', '{}'::jsonb),
    :'rotatedCodeID'::uuid,
    'Should return the caller-provided code when rotating an existing one'
);

-- Should replace the existing code and refresh its timestamp
select results_eq(
    format(
        $$
            select
                email_verification_code_id,
                created_at > '2024-01-01 00:00:00+00'::timestamptz
            from email_verification_code
            where user_id = %L::uuid
        $$,
        :'userWithCodeID'
    ),
    format($$values (%L::uuid, true)$$, :'rotatedCodeID'),
    'Should replace the existing code and refresh its timestamp'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
