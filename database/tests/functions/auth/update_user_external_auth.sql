-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set conflictUserID '0a0e0000-0000-0000-0000-000000000001'
\set identityConflictUserID '0a0e0000-0000-0000-0000-000000000006'
\set preRegisteredUserID '0a0e0000-0000-0000-0000-000000000002'
\set userID '0a0e0000-0000-0000-0000-000000000003'
\set userWithoutNameID '0a0e0000-0000-0000-0000-000000000004'
\set userWithoutProviderID '0a0e0000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    name,
    provider,
    registration_status,
    username
) values (
    :'conflictUserID',
    'conflict-hash',
    'conflict@example.com',
    true,
    'Conflict User',
    null,
    'registered',
    'conflict-user'
), (
    :'identityConflictUserID',
    'identity-conflict-hash',
    'identity-conflict@example.com',
    true,
    'Identity Conflict User',
    jsonb_build_object(
        'linuxfoundation', jsonb_build_object(
            'issuer', 'https://issuer.example.com',
            'subject', 'auth0|conflict',
            'username', 'lf-conflict'
        )
    ),
    'registered',
    'identity-conflict-user'
), (
    :'preRegisteredUserID',
    'pre-registered-hash',
    'pre-registered@example.com',
    false,
    'Pre Registered User',
    null,
    'pre-registered',
    'pre-registered-user'
), (
    :'userID',
    'test-hash',
    'old@example.com',
    true,
    'Old Name',
    jsonb_build_object(
        'github', jsonb_build_object(
            'username', 'octocat'
        )
    ),
    'registered',
    'test-user'
), (
    :'userWithoutNameID',
    'no-name-hash',
    'no-name-old@example.com',
    true,
    null,
    null,
    'registered',
    'no-name-user'
), (
    :'userWithoutProviderID',
    'no-provider-hash',
    'no-provider-old@example.com',
    true,
    'No Provider User',
    null,
    'registered',
    'no-provider-user'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should sync verified external email and return the refreshed user.
select is(
    update_user_external_auth(
        :'userID',
        jsonb_build_object(
            'email', 'New@Example.com',
            'name', 'New Name',
            'provider', jsonb_build_object(
                'linuxfoundation', jsonb_build_object(
                    'issuer', 'https://issuer.example.com',
                    'subject', 'auth0|user',
                    'username', 'lf-user'
                )
            )
        )
    )::jsonb->>'email',
    'new@example.com',
    'Should sync verified external email and return the refreshed user'
);

-- Should merge provider metadata across providers.
select results_eq(
    format($$
        select
            email,
            email_verified,
            name,
            provider
        from "user"
        where user_id = %L::uuid
    $$, :'userID'),
    $$
        values (
            'new@example.com',
            true,
            'New Name',
            '{
                "github": {"username": "octocat"},
                "linuxfoundation": {
                    "issuer": "https://issuer.example.com",
                    "subject": "auth0|user",
                    "username": "lf-user"
                }
            }'::jsonb
        )
    $$,
    'Should merge provider metadata across providers'
);

-- Should allow external email sync without provider metadata.
select is(
    update_user_external_auth(
        :'userWithoutProviderID',
        jsonb_build_object('email', 'No-Provider-New@Example.com')
    )::jsonb->>'email',
    'no-provider-new@example.com',
    'Should allow external email sync without provider metadata'
);

-- Should coalesce missing names in returned external-auth payloads.
select is(
    update_user_external_auth(
        :'userWithoutNameID',
        jsonb_build_object('email', 'No-Name-New@Example.com')
    )::jsonb->>'name',
    '',
    'Should coalesce missing names in returned external-auth payloads'
);

-- Should preserve existing values when metadata is not supplied.
select results_eq(
    format($$
        select
            name,
            provider
        from "user"
        where user_id = %L::uuid
    $$, :'userWithoutProviderID'),
    $$
        values (
            'No Provider User',
            null::jsonb
        )
    $$,
    'Should preserve existing values when metadata is not supplied'
);

-- Should reject syncing an email owned by another user.
select throws_ok(
    format($$ select update_user_external_auth(
        %L::uuid,
        '{"email": "conflict@example.com"}'::jsonb
    ) $$, :'userID'),
    'external auth email belongs to another user',
    'Should reject syncing an email owned by another user'
);

-- Should treat LF OIDC identity values as exact.
select is(
    update_user_external_auth(
        :'userWithoutProviderID',
        jsonb_build_object(
            'email', 'Identity-Space@Example.com',
            'provider', jsonb_build_object(
                'linuxfoundation', jsonb_build_object(
                    'issuer', ' https://issuer.example.com',
                    'subject', 'auth0|conflict',
                    'username', 'lf-conflict'
                )
            )
        )
    )::jsonb->>'email',
    'identity-space@example.com',
    'Should treat LF OIDC identity values as exact'
);

-- Should reject syncing an LF OIDC identity owned by another user.
select throws_ok(
    format($$ select update_user_external_auth(
        %L::uuid,
        '{
            "email": "identity-new@example.com",
            "provider": {
                "linuxfoundation": {
                    "issuer": "https://issuer.example.com",
                    "subject": "auth0|conflict",
                    "username": "lf-conflict"
                }
            }
        }'::jsonb
    ) $$, :'userWithoutNameID'),
    'external auth identity belongs to another user',
    'Should reject syncing an LF OIDC identity owned by another user'
);

-- Should reject pre-registered users.
select throws_ok(
    format($$ select update_user_external_auth(
        %L::uuid,
        '{"email": "activated@example.com"}'::jsonb
    ) $$, :'preRegisteredUserID'),
    'registered external-auth user not found',
    'Should reject pre-registered users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
