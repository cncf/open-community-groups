-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set untouchedUserID '00000000-0000-0000-0000-000000000131'
\set userID '00000000-0000-0000-0000-000000000132'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Target user
insert into "user" (
    auth_hash,
    email,
    email_verified,
    password,
    user_id,
    username
) values (
    'initial_hash_target',
    'target@example.com',
    true,
    'old_password',
    :'userID',
    'target-user'
);

-- Control user
insert into "user" (
    auth_hash,
    email,
    email_verified,
    password,
    user_id,
    username
) values (
    'initial_hash_control',
    'control@example.com',
    true,
    'control_password',
    :'untouchedUserID',
    'control-user'
);

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
