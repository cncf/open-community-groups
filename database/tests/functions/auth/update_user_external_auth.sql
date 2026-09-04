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

-- Registered user whose email conflicts with external auth sync
select fx_user(:'conflictUserID', jsonb_build_object('email', 'conflict@example.com'));

-- Registered user whose Linux Foundation identity conflicts with external auth sync
select fx_user(:'identityConflictUserID', jsonb_build_object('provider', jsonb_build_object(
    'linuxfoundation', jsonb_build_object(
        'issuer', 'https://issuer.example.com',
        'subject', 'auth0|conflict',
        'username', 'lf-conflict'
    )
)));

-- Pre-registered user rejected by external auth sync
select fx_user(:'preRegisteredUserID', jsonb_build_object(
    'email_verified', false,
    'registration_status', 'pre-registered'
));

-- Registered user refreshed by external auth sync
select fx_user(:'userID', jsonb_build_object(
    'email', 'old@example.com',
    'provider', jsonb_build_object(
        'github', jsonb_build_object(
            'username', 'octocat'
        )
    )
));

-- Registered user without a name returned by external auth sync
select fx_user(:'userWithoutNameID', jsonb_build_object('email', 'no-name-old@example.com'));

-- Registered user without provider metadata refreshed by external auth sync
select fx_user(:'userWithoutProviderID', jsonb_build_object(
    'name', 'No Provider User'
));

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
    'OCG01',
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
    'OCG01',
    'external auth identity belongs to another user',
    'Should reject syncing an LF OIDC identity owned by another user'
);

-- Should reject pre-registered users.
select throws_ok(
    format($$ select update_user_external_auth(
        %L::uuid,
        '{"email": "activated@example.com"}'::jsonb
    ) $$, :'preRegisteredUserID'),
    'OCG01',
    'registered external-auth user not found',
    'Should reject pre-registered users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
