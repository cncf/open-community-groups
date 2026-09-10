-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

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

-- Should not modify other users
select is(
    (select password from "user" where user_id = :'untouchedUserID'::uuid),
    'control_password',
    'Should not modify other users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
