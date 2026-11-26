-- Tests password reset token constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userCascadeID 'c0250000-0000-0000-0000-000000000001'
\set userExistingID 'c0250000-0000-0000-0000-000000000002'
\set userOtherID 'c0250000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User whose password reset token cascades on user deletion
select fx_user(:'userCascadeID');

-- User holding an existing password reset token
select fx_user(:'userExistingID');

-- Second user attempting to reuse an existing token hash
select fx_user(:'userOtherID');

-- Password reset token deleted through user cascade
insert into password_reset_token (token_hash, user_id)
values (digest('c025-cascade-token', 'sha256'), :'userCascadeID');

-- Existing password reset token used for uniqueness checks
insert into password_reset_token (token_hash, user_id)
values (digest('c025-existing-token', 'sha256'), :'userExistingID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should delete password reset tokens when users are deleted
select lives_ok(
    format($$delete from "user" where user_id = %L::uuid$$, :'userCascadeID'),
    'Should delete users holding password reset tokens'
);
select is(
    (
        select count(*)::int
        from password_reset_token
        where user_id = :'userCascadeID'
    ),
    0,
    'Should delete password reset tokens when users are deleted'
);

-- Should reject duplicate token hashes across users
select throws_ok(
    format(
        $$
            insert into password_reset_token (token_hash, user_id)
            values (digest('c025-existing-token', 'sha256'), %L::uuid)
        $$,
        :'userOtherID'
    ),
    '23505',
    'duplicate key value violates unique constraint "password_reset_token_pkey"',
    'Should reject duplicate token hashes across users'
);

-- Should reject multiple active tokens for the same user
select throws_ok(
    format(
        $$
            insert into password_reset_token (token_hash, user_id)
            values (digest('c025-second-token', 'sha256'), %L::uuid)
        $$,
        :'userExistingID'
    ),
    '23505',
    'duplicate key value violates unique constraint "password_reset_token_user_id_key"',
    'Should reject multiple active tokens for the same user'
);

-- Should reject token hashes longer than 32 bytes
select throws_ok(
    format(
        $$
            insert into password_reset_token (token_hash, user_id)
            values (decode(repeat('ab', 33), 'hex'), %L::uuid)
        $$,
        :'userOtherID'
    ),
    '23514',
    'new row for relation "password_reset_token" violates check constraint "password_reset_token_token_hash_check"',
    'Should reject token hashes longer than 32 bytes'
);

-- Should reject token hashes shorter than 32 bytes
select throws_ok(
    format(
        $$
            insert into password_reset_token (token_hash, user_id)
            values (decode('deadbeef', 'hex'), %L::uuid)
        $$,
        :'userOtherID'
    ),
    '23514',
    'new row for relation "password_reset_token" violates check constraint "password_reset_token_token_hash_check"',
    'Should reject token hashes shorter than 32 bytes'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
