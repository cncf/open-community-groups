-- Tests signing up users with verified and unverified emails.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(19);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set defaultVerificationCodeID '0a000000-0000-0000-0000-000000000001'
\set existingEmailUserID '0a000000-0000-0000-0000-000000000005'
\set missingTemplateVerificationCodeID '0a000000-0000-0000-0000-000000000002'
\set takenUsernameUserID '0a000000-0000-0000-0000-000000000004'
\set unverifiedVerificationCodeID '0a000000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User holding the email reused with different case by the duplicate scenario
select fx_user(:'existingEmailUserID', jsonb_build_object(
    'email', 'sign-up-user-existing@example.com'
));

-- User holding the username requested by the suffix scenario
select fx_user(:'takenUsernameUserID', jsonb_build_object(
    'username', 'sign-up-user-taken'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Sign up a user with a verified email
select to_jsonb(signed_up) as "verifiedSignUp"
from sign_up_user(
    jsonb_build_object(
        'email', 'verified-sign-up@example.com',
        'username', 'verifieduser',
        'name', 'Verified User',
        'password', 'hashedpassword123',
        'provider', jsonb_build_object(
            'github', jsonb_build_object(
                'username', 'verifieduser-gh'
            )
        )
    ),
    true,
    null::uuid,
    null::jsonb
) as signed_up \gset

-- Should return the verified user
select is(
    (:'verifiedSignUp'::jsonb->'user') - 'auth_hash' - 'user_id',
    '{
        "email": "verified-sign-up@example.com",
        "email_verified": true,
        "name": "Verified User",
        "provider": {
            "github": {
                "username": "verifieduser-gh"
            }
        },
        "username": "verifieduser"
    }'::jsonb,
    'Should return the verified user'
);

-- Should generate a 64 character auth hash for the verified user
select is(
    length(:'verifiedSignUp'::jsonb->'user'->>'auth_hash'),
    64,
    'Should generate a 64 character auth hash for the verified user'
);

-- Should not return a verification code when email_verified is true
select is(
    :'verifiedSignUp'::jsonb->'verification_code',
    'null'::jsonb,
    'Should not return a verification code when email_verified is true'
);

-- Should not store a verification code when email_verified is true
select is_empty(
    format(
        $$select 1 from email_verification_code where user_id = %L::uuid$$,
        :'verifiedSignUp'::jsonb->'user'->>'user_id'
    ),
    'Should not store a verification code when email_verified is true'
);

-- Should not enqueue a notification when email_verified is true
select is_empty(
    format(
        $$select 1 from notification where user_id = %L::uuid$$,
        :'verifiedSignUp'::jsonb->'user'->>'user_id'
    ),
    'Should not enqueue a notification when email_verified is true'
);

-- Sign up a user with an unverified email
select to_jsonb(signed_up) as "unverifiedSignUp"
from sign_up_user(
    jsonb_build_object(
        'email', 'unverified-sign-up@example.com',
        'username', 'unverifieduser',
        'name', 'Unverified User',
        'password', 'hashedpassword456'
    ),
    false,
    :'unverifiedVerificationCodeID',
    jsonb_build_object(
        'link', 'https://example.test/verify-email/' || :'unverifiedVerificationCodeID',
        'theme', jsonb_build_object('primary_color', '#123456')
    )
) as signed_up \gset

-- Should return the unverified user
select is(
    (:'unverifiedSignUp'::jsonb->'user') - 'auth_hash' - 'user_id',
    '{
        "email": "unverified-sign-up@example.com",
        "email_verified": false,
        "name": "Unverified User",
        "username": "unverifieduser"
    }'::jsonb,
    'Should return the unverified user'
);

-- Should generate a 64 character auth hash for the unverified user
select is(
    length(:'unverifiedSignUp'::jsonb->'user'->>'auth_hash'),
    64,
    'Should generate a 64 character auth hash for the unverified user'
);

-- Should return the caller-provided verification code when email_verified is false
select is(
    (:'unverifiedSignUp'::jsonb->>'verification_code')::uuid,
    :'unverifiedVerificationCodeID'::uuid,
    'Should return the caller-provided verification code when email_verified is false'
);

-- Should store the caller-provided verification code for the unverified user
select results_eq(
    format(
        $$
            select user_id
            from email_verification_code
            where email_verification_code_id = %L::uuid
        $$,
        :'unverifiedVerificationCodeID'
    ),
    format(
        $$values (%L::uuid)$$,
        :'unverifiedSignUp'::jsonb->'user'->>'user_id'
    ),
    'Should store the caller-provided verification code for the unverified user'
);

-- Should enqueue caller-provided email verification notification data when email_verified is false
select ok(
    exists (
        select 1
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        join "user" u using (user_id)
        where n.kind = 'email-verification'
        and u.email = 'unverified-sign-up@example.com'
        and ntd.data = jsonb_build_object(
            'link',
            'https://example.test/verify-email/' || :'unverifiedVerificationCodeID',
            'theme',
            jsonb_build_object('primary_color', '#123456')
        )
    ),
    'Should enqueue caller-provided email verification notification data when email_verified is false'
);

-- Sign up a user without the email_verified argument
select to_jsonb(signed_up) as "defaultSignUp"
from sign_up_user(
    jsonb_build_object(
        'email', 'default@example.com',
        'username', 'defaultuser',
        'name', 'Default User',
        'password', 'hashedpassword789'
    ),
    p_verification_code => :'defaultVerificationCodeID',
    p_verification_template_data => jsonb_build_object(
        'link', 'https://example.test/verify-email/' || :'defaultVerificationCodeID',
        'theme', jsonb_build_object('primary_color', '#654321')
    )
) as signed_up \gset

-- Should default to false when email_verified is omitted
select is(
    (:'defaultSignUp'::jsonb->'user') - 'auth_hash' - 'user_id',
    '{
        "email": "default@example.com",
        "email_verified": false,
        "name": "Default User",
        "username": "defaultuser"
    }'::jsonb,
    'Should default to false when email_verified is omitted'
);

-- Should generate a 64 character auth hash when email_verified is omitted
select is(
    length(:'defaultSignUp'::jsonb->'user'->>'auth_hash'),
    64,
    'Should generate a 64 character auth hash when email_verified is omitted'
);

-- Should return the caller-provided verification code when email_verified is omitted
select is(
    (:'defaultSignUp'::jsonb->>'verification_code')::uuid,
    :'defaultVerificationCodeID'::uuid,
    'Should return the caller-provided verification code when email_verified is omitted'
);

-- Should enqueue default email verification notification with the verification link
select ok(
    exists (
        select 1
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        join "user" u using (user_id)
        where n.kind = 'email-verification'
        and u.email = 'default@example.com'
        and ntd.data = jsonb_build_object(
            'link',
            'https://example.test/verify-email/' || :'defaultVerificationCodeID',
            'theme',
            jsonb_build_object('primary_color', '#654321')
        )
    ),
    'Should enqueue default email verification notification with the verification link'
);

-- Should reject unverified signup without a verification code
select throws_ok(
    $$
        select * from sign_up_user(
            jsonb_build_object(
                'email', 'missing-code@example.com',
                'username', 'missingcode',
                'name', 'Missing Code',
                'password', 'hashedpassword000'
            ),
            false,
            null::uuid,
            '{}'::jsonb
        )
    $$,
    'P0001',
    'verification code is required to send verification email',
    'Should reject unverified signup without a verification code'
);

-- Should reject unverified signup without verification template data
select throws_ok(
    format(
        $$
            select * from sign_up_user(
                jsonb_build_object(
                    'email', 'missing-template@example.com',
                    'username', 'missingtemplate',
                    'name', 'Missing Template',
                    'password', 'hashedpassword000'
                ),
                false,
                %L::uuid,
                null::jsonb
            )
        $$,
        :'missingTemplateVerificationCodeID'
    ),
    'P0001',
    'verification template data is required to send verification email',
    'Should reject unverified signup without verification template data'
);

-- Should resolve a unique username when the requested one is taken
select is(
    (
        select "user"::jsonb->>'username'
        from sign_up_user(
            jsonb_build_object(
                'email', 'sign-up-user-taken@example.com',
                'username', 'sign-up-user-taken',
                'name', 'Taken Username User',
                'password', 'hashedpassword111'
            ),
            true,
            null::uuid,
            null::jsonb
        )
    ),
    'sign-up-user-taken2',
    'Should resolve a unique username when the requested one is taken'
);

-- Should store the email lowercased
with mixed_case_user_result as (
    select * from sign_up_user(
        jsonb_build_object(
            'email', 'Mixed.Case@Example.COM',
            'username', 'mixedcaseuser',
            'name', 'Mixed Case User',
            'password', 'hashedpassword555'
        ),
        true,
        null::uuid,
        null::jsonb
    )
)
select is(
    (select "user"::jsonb->>'email' from mixed_case_user_result),
    'mixed.case@example.com',
    'Should store the email lowercased'
);

-- Should reject an email that differs only in case from an existing one
select throws_ok(
    $$
        select * from sign_up_user(
            jsonb_build_object(
                'email', 'SIGN-UP-USER-EXISTING@example.com',
                'username', 'anotheruser',
                'name', 'Another User',
                'password', 'hashedpassword666'
            ),
            true,
            null::uuid,
            null::jsonb
        )
    $$,
    '23505',
    'duplicate key value violates unique constraint "user_email_lower_idx"',
    'Should reject an email that differs only in case from an existing one'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
