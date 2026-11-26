-- Tests batched deletion of expired password reset tokens.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userActiveID '0a130000-0000-0000-0000-000000000001'
\set userExpiredBoundaryID '0a130000-0000-0000-0000-000000000002'
\set userExpiredNewerID '0a130000-0000-0000-0000-000000000003'
\set userExpiredOldestID '0a130000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User holding an active password reset token
select fx_user(:'userActiveID');

-- User holding a token expiring at the 1-hour boundary
select fx_user(:'userExpiredBoundaryID');

-- User holding a newer expired password reset token
select fx_user(:'userExpiredNewerID');

-- User holding the oldest expired password reset token
select fx_user(:'userExpiredOldestID');

-- Active token within the 1-hour validity window
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a13-active', 'sha256'),
    current_timestamp - interval '59 minutes',
    :'userActiveID'
);

-- Token sitting on the 1-hour expiration boundary
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a13-expired-boundary', 'sha256'),
    current_timestamp - interval '1 hour',
    :'userExpiredBoundaryID'
);

-- More recently expired token included in the first batch
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a13-expired-newer', 'sha256'),
    current_timestamp - interval '2 hours',
    :'userExpiredNewerID'
);

-- Oldest expired token included first in batch order
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a13-expired-oldest', 'sha256'),
    current_timestamp - interval '3 hours',
    :'userExpiredOldestID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a batch size above the limit
select throws_ok(
    $$select delete_expired_password_reset_tokens(1001)$$,
    'P0001',
    'password reset token cleanup batch size must be between 1 and 1000',
    'Should reject a batch size above the limit'
);

-- Should reject a negative batch size
select throws_ok(
    $$select delete_expired_password_reset_tokens(-1)$$,
    'P0001',
    'password reset token cleanup batch size must be between 1 and 1000',
    'Should reject a negative batch size'
);

-- Should reject a null batch size
select throws_ok(
    $$select delete_expired_password_reset_tokens(null)$$,
    'P0001',
    'password reset token cleanup batch size must be between 1 and 1000',
    'Should reject a null batch size'
);

-- Should reject a zero batch size
select throws_ok(
    $$select delete_expired_password_reset_tokens(0)$$,
    'P0001',
    'password reset token cleanup batch size must be between 1 and 1000',
    'Should reject a zero batch size'
);

-- Should delete at most one bounded batch of oldest expired tokens
select is(
    delete_expired_password_reset_tokens(2),
    2,
    'Should delete at most one bounded batch of oldest expired tokens'
);

-- Should leave remaining expired and active tokens after the first batch
select results_eq(
    $$
        select user_id
        from password_reset_token
        order by user_id
    $$,
    format(
        $$values (%L::uuid), (%L::uuid)$$,
        :'userActiveID',
        :'userExpiredBoundaryID'
    ),
    'Should leave remaining expired and active tokens after the first batch'
);

-- Should delete the remaining boundary-expired token with the default batch size
select is(
    delete_expired_password_reset_tokens(),
    1,
    'Should delete the remaining boundary-expired token with the default batch size'
);

-- Should leave only active tokens after draining expired tokens
select results_eq(
    $$
        select user_id
        from password_reset_token
        order by user_id
    $$,
    format($$values (%L::uuid)$$, :'userActiveID'),
    'Should leave only active tokens after draining expired tokens'
);

-- Should return zero when no expired tokens remain
select is(
    delete_expired_password_reset_tokens(),
    0,
    'Should return zero when no expired tokens remain'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
