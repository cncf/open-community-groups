-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only public provider metadata.
select is(
    get_public_user_provider(jsonb_build_object(
        'github', jsonb_build_object(
            'username', 'octocat'
        ),
        'linuxfoundation', jsonb_build_object(
            'issuer', 'https://issuer.example.com',
            'subject', 'auth0|user',
            'username', 'lf-user'
        )
    )),
    jsonb_build_object(
        'github', jsonb_build_object(
            'username', 'octocat'
        ),
        'linuxfoundation', jsonb_build_object(
            'username', 'lf-user'
        )
    ),
    'Should return only public provider metadata'
);

-- Should trim public provider usernames.
select is(
    get_public_user_provider(jsonb_build_object(
        'github', jsonb_build_object(
            'username', '  octocat  '
        ),
        'linuxfoundation', jsonb_build_object(
            'username', '  lf-user  '
        )
    )),
    jsonb_build_object(
        'github', jsonb_build_object(
            'username', 'octocat'
        ),
        'linuxfoundation', jsonb_build_object(
            'username', 'lf-user'
        )
    ),
    'Should trim public provider usernames'
);

-- Should return GitHub provider metadata without Linux Foundation metadata.
select is(
    get_public_user_provider(jsonb_build_object(
        'github', jsonb_build_object(
            'username', 'octocat'
        )
    )),
    jsonb_build_object(
        'github', jsonb_build_object(
            'username', 'octocat'
        )
    ),
    'Should return GitHub provider metadata without Linux Foundation metadata'
);

-- Should ignore blank provider usernames.
select is(
    get_public_user_provider(jsonb_build_object(
        'github', jsonb_build_object(
            'username', '   '
        ),
        'linuxfoundation', jsonb_build_object(
            'username', '   '
        )
    )),
    null::jsonb,
    'Should ignore blank provider usernames'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
