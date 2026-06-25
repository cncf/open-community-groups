-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set registeredUserID '0a0d0000-0000-0000-0000-000000000001'
\set unverifiedUserID '0a0d0000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    password,
    provider,
    registration_status,
    username
) values (
    :'registeredUserID',
    'registered-hash',
    'registered@example.com',
    true,
    'registered-password',
    jsonb_build_object(
        'linuxfoundation', jsonb_build_object(
            'username', 'lf-registered'
        ) || jsonb_build_object(
            'issuer', 'https://issuer.example.com',
            'subject', 'auth0|registered'
        )
    ),
    'registered',
    'registered-user'
), (
    :'unverifiedUserID',
    'unverified-hash',
    'unverified@example.com',
    false,
    null,
    jsonb_build_object(
        'linuxfoundation', jsonb_build_object(
            'username', 'lf-unverified'
        ) || jsonb_build_object(
            'issuer', 'https://issuer.example.com',
            'subject', 'auth0|unverified'
        )
    ),
    'registered',
    'unverified-user'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return verified registered users by LF OIDC identity.
select is(
    get_user_by_linuxfoundation_identity_for_external_auth(
        'https://issuer.example.com',
        'auth0|registered'
    )::jsonb->>'user_id',
    :'registeredUserID',
    'Should return verified registered users by LF OIDC identity'
);

-- Should not include password in external auth lookup.
select is(
    get_user_by_linuxfoundation_identity_for_external_auth(
        'https://issuer.example.com',
        'auth0|registered'
    )::jsonb ? 'password',
    false,
    'Should not include password in LF identity lookup'
);

-- Should coalesce missing names for external-auth payloads.
select is(
    get_user_by_linuxfoundation_identity_for_external_auth(
        'https://issuer.example.com',
        'auth0|registered'
    )::jsonb->>'name',
    '',
    'Should coalesce missing names for external-auth payloads'
);

-- Should not return unverified registered users.
select is(
    get_user_by_linuxfoundation_identity_for_external_auth(
        'https://issuer.example.com',
        'auth0|unverified'
    )::jsonb,
    null::jsonb,
    'Should not return unverified registered users'
);

-- Should return null when the LF OIDC identity does not exist.
select is(
    get_user_by_linuxfoundation_identity_for_external_auth(
        'https://issuer.example.com',
        'auth0|missing'
    )::jsonb,
    null::jsonb,
    'Should return null when the LF OIDC identity does not exist'
);

-- Should match LF OIDC issuer case-sensitively.
select is(
    get_user_by_linuxfoundation_identity_for_external_auth(
        'https://ISSUER.example.com',
        'auth0|registered'
    )::jsonb,
    null::jsonb,
    'Should match LF OIDC issuer case-sensitively'
);

-- Should match LF OIDC subject case-sensitively.
select is(
    get_user_by_linuxfoundation_identity_for_external_auth(
        'https://issuer.example.com',
        'AUTH0|registered'
    )::jsonb,
    null::jsonb,
    'Should match LF OIDC subject case-sensitively'
);

-- Should match LF OIDC identity exactly.
select is(
    get_user_by_linuxfoundation_identity_for_external_auth(
        ' https://issuer.example.com',
        'auth0|registered '
    )::jsonb,
    null::jsonb,
    'Should match LF OIDC identity exactly'
);

-- Should return null when the LF OIDC identity is incomplete.
select is(
    get_user_by_linuxfoundation_identity_for_external_auth(
        'https://issuer.example.com',
        ''
    )::jsonb,
    null::jsonb,
    'Should return null when the LF OIDC identity is incomplete'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
