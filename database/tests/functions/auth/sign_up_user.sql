-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set defaultVerificationCodeID '0a020000-0000-0000-0000-000000000001'
\set missingTemplateVerificationCodeID '0a020000-0000-0000-0000-000000000002'
\set unverifiedVerificationCodeID '0a020000-0000-0000-0000-000000000003'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should not generate verification code when email_verified is true
with verified_user_result as (
    select * from sign_up_user(
        jsonb_build_object(
            'email', 'verified@example.com',
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
    )
)
select ok(
    ("user"::jsonb - 'user_id'::text - 'auth_hash'::text = '{
        "email": "verified@example.com",
        "email_verified": true,
        "optional_notifications_enabled": true,
        "name": "Verified User",
        "provider": {
            "github": {
                "username": "verifieduser-gh"
            }
        },
        "username": "verifieduser"
    }'::jsonb)
    and ("user"::jsonb ? 'auth_hash')
    and length(("user"::jsonb->>'auth_hash')) = 64
    and verification_code is null,
    'Should not generate verification code when email_verified is true'
) from verified_user_result;

-- Should store caller-provided verification code when email_verified is false
with unverified_user_result as (
    select * from sign_up_user(
        jsonb_build_object(
            'email', 'unverified@example.com',
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
    )
)
select ok(
    ("user"::jsonb - 'user_id'::text - 'auth_hash'::text = '{
        "email": "unverified@example.com",
        "email_verified": false,
        "optional_notifications_enabled": true,
        "name": "Unverified User",
        "username": "unverifieduser"
    }'::jsonb)
    and ("user"::jsonb ? 'auth_hash')
    and length(("user"::jsonb->>'auth_hash')) = 64
    and verification_code = :'unverifiedVerificationCodeID'::uuid,
    'Should store caller-provided verification code when email_verified is false'
) from unverified_user_result;

-- Should enqueue caller-provided email verification notification data when email_verified is false.
select ok(
    exists (
        select 1
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        join "user" u using (user_id)
        where n.kind = 'email-verification'
        and u.email = 'unverified@example.com'
        and ntd.data = jsonb_build_object(
            'link',
            'https://example.test/verify-email/' || :'unverifiedVerificationCodeID',
            'theme',
            jsonb_build_object('primary_color', '#123456')
        )
    ),
    'Should enqueue caller-provided email verification notification data when email_verified is false'
);

-- Should default to false and store caller-provided verification code when email_verified is omitted
with default_user_result as (
    select * from sign_up_user(
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
    )
)
select ok(
    ("user"::jsonb - 'user_id'::text - 'auth_hash'::text = '{
        "email": "default@example.com",
        "email_verified": false,
        "optional_notifications_enabled": true,
        "name": "Default User",
        "username": "defaultuser"
    }'::jsonb)
    and ("user"::jsonb ? 'auth_hash')
    and length(("user"::jsonb->>'auth_hash')) = 64
    and verification_code = :'defaultVerificationCodeID'::uuid,
    'Should default to false and store caller-provided verification code when email_verified is omitted'
) from default_user_result;

-- Should enqueue default email verification notification with the verification link.
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

-- Should reject unverified signup without a verification code.
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
    'verification code is required to send verification email',
    'Should reject unverified signup without a verification code'
);

-- Should reject unverified signup without verification template data.
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
    'verification template data is required to send verification email',
    'Should reject unverified signup without verification template data'
);

-- Should add numeric suffix starting at 2 for duplicate usernames
with duplicate_user_1 as (
    select * from sign_up_user(
        jsonb_build_object(
            'email', 'duplicate1@example.com',
            'username', 'duplicateuser',
            'name', 'First Duplicate User',
            'password', 'hashedpassword111'
        ),
        true,
        null::uuid,
        null::jsonb
    )
),
duplicate_user_2 as (
    select * from sign_up_user(
        jsonb_build_object(
            'email', 'duplicate2@example.com',
            'username', 'duplicateuser',
            'name', 'Second Duplicate User',
            'password', 'hashedpassword222'
        ),
        true,
        null::uuid,
        null::jsonb
    )
)
select ok(
    (select "user"::jsonb->>'username' from duplicate_user_1) = 'duplicateuser'
    and (select "user"::jsonb->>'username' from duplicate_user_2) = 'duplicateuser2',
    'Should add numeric suffix starting at 2 for duplicate usernames'
);

-- Should increment suffix properly for multiple duplicate usernames
with duplicate_user_3 as (
    select * from sign_up_user(
        jsonb_build_object(
            'email', 'duplicate3@example.com',
            'username', 'duplicateuser',
            'name', 'Third Duplicate User',
            'password', 'hashedpassword333'
        ),
        true,
        null::uuid,
        null::jsonb
    )
),
duplicate_user_4 as (
    select * from sign_up_user(
        jsonb_build_object(
            'email', 'duplicate4@example.com',
            'username', 'duplicateuser',
            'name', 'Fourth Duplicate User',
            'password', 'hashedpassword444'
        ),
        true,
        null::uuid,
        null::jsonb
    )
)
select ok(
    (select "user"::jsonb->>'username' from duplicate_user_3) = 'duplicateuser3'
    and (select "user"::jsonb->>'username' from duplicate_user_4) = 'duplicateuser4',
    'Should increment suffix properly for multiple duplicate usernames (3, 4, etc)'
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
                'email', 'VERIFIED@example.com',
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
    null,
    'Should reject an email that differs only in case from an existing one'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
