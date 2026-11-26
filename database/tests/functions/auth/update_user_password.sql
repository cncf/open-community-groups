-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set untouchedUserID '0a0b0000-0000-0000-0000-000000000001'
\set userID '0a0b0000-0000-0000-0000-000000000002'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Control user whose password remains unchanged
select fx_user(:'untouchedUserID', jsonb_build_object('password', 'control_password'));

-- Target user whose password and auth hash are updated
select fx_user(:'userID', jsonb_build_object(
    'auth_hash', 'initial_hash_target',
    'password', 'old_password',
    'username', 'target-user'
));

-- Active password reset token that must be revoked when the password changes
insert into password_reset_token (token_hash, user_id)
values (digest('0a0b-active-reset-token', 'sha256'), :'userID');

-- Active password reset token belonging to the control user that must stay untouched
insert into password_reset_token (token_hash, user_id)
values (digest('0a0b-control-reset-token', 'sha256'), :'untouchedUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update password for target user
select lives_ok(
    format(
        $$select update_user_password(%L::uuid, %L::text)$$,
        :'userID',
        'new_password'
    ),
    'Should update password for target user'
);

-- Should persist the new password for target user
select is(
    (select password from "user" where user_id = :'userID'::uuid),
    'new_password',
    'Should persist the new password for target user'
);

-- Should rotate auth_hash for target user
select isnt(
    (select auth_hash from "user" where user_id = :'userID'::uuid),
    'initial_hash_target',
    'Should rotate auth_hash for target user'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            resource_type,
            resource_id
        from audit_log
    $$,
    format($$
        values (
            'user_password_updated',
            %L::uuid,
            'target-user',
            'user',
            %L::uuid
        )
    $$, :'userID', :'userID'),
    'Should create the expected audit row'
);

-- Should revoke active password reset tokens for target user
select is(
    (select count(*)::int from password_reset_token where user_id = :'userID'::uuid),
    0,
    'Should revoke active password reset tokens for target user'
);

-- Should not modify other users or their reset tokens
select is(
    (select password from "user" where user_id = :'untouchedUserID'::uuid),
    'control_password',
    'Should not modify other users'
);
select is(
    (select count(*)::int from password_reset_token where user_id = :'untouchedUserID'::uuid),
    1,
    'Should leave other users reset tokens intact'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
