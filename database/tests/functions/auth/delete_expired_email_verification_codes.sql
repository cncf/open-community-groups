-- Tests batched deletion of expired email verification codes.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set codeActiveID '0a110000-0000-0000-0000-000000000011'
\set codeExpiredBoundaryID '0a110000-0000-0000-0000-000000000012'
\set codeExpiredNewerID '0a110000-0000-0000-0000-000000000013'
\set codeExpiredOldestID '0a110000-0000-0000-0000-000000000014'
\set userActiveID '0a110000-0000-0000-0000-000000000001'
\set userExpiredBoundaryID '0a110000-0000-0000-0000-000000000002'
\set userExpiredNewerID '0a110000-0000-0000-0000-000000000003'
\set userExpiredOldestID '0a110000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Unverified user holding an active verification code
select fx_user(:'userActiveID', jsonb_build_object('email_verified', false));

-- Unverified user holding a verification code expiring at the 24-hour boundary
select fx_user(:'userExpiredBoundaryID', jsonb_build_object('email_verified', false));

-- Unverified user holding a newer expired verification code
select fx_user(:'userExpiredNewerID', jsonb_build_object('email_verified', false));

-- Unverified user holding the oldest expired verification code
select fx_user(:'userExpiredOldestID', jsonb_build_object('email_verified', false));

-- Active verification code within the 24-hour window
insert into email_verification_code (email_verification_code_id, created_at, user_id)
values (
    :'codeActiveID',
    current_timestamp - interval '23 hours',
    :'userActiveID'
);

-- Verification code sitting on the 24-hour expiration boundary
insert into email_verification_code (email_verification_code_id, created_at, user_id)
values (
    :'codeExpiredBoundaryID',
    current_timestamp - interval '1 day',
    :'userExpiredBoundaryID'
);

-- More recently expired verification code included in the first batch
insert into email_verification_code (email_verification_code_id, created_at, user_id)
values (
    :'codeExpiredNewerID',
    current_timestamp - interval '25 hours',
    :'userExpiredNewerID'
);

-- Oldest expired verification code included first in batch order
insert into email_verification_code (email_verification_code_id, created_at, user_id)
values (
    :'codeExpiredOldestID',
    current_timestamp - interval '48 hours',
    :'userExpiredOldestID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a batch size above the limit
select throws_ok(
    $$select delete_expired_email_verification_codes(1001)$$,
    'P0001',
    'email verification code cleanup batch size must be between 1 and 1000',
    'Should reject a batch size above the limit'
);

-- Should reject a negative batch size
select throws_ok(
    $$select delete_expired_email_verification_codes(-1)$$,
    'P0001',
    'email verification code cleanup batch size must be between 1 and 1000',
    'Should reject a negative batch size'
);

-- Should reject a null batch size
select throws_ok(
    $$select delete_expired_email_verification_codes(null)$$,
    'P0001',
    'email verification code cleanup batch size must be between 1 and 1000',
    'Should reject a null batch size'
);

-- Should reject a zero batch size
select throws_ok(
    $$select delete_expired_email_verification_codes(0)$$,
    'P0001',
    'email verification code cleanup batch size must be between 1 and 1000',
    'Should reject a zero batch size'
);

-- Should delete at most one bounded batch of oldest expired verification codes
select is(
    delete_expired_email_verification_codes(2),
    2,
    'Should delete at most one bounded batch of oldest expired verification codes'
);

-- Should leave remaining expired and active verification codes after the first batch
select results_eq(
    $$
        select email_verification_code_id
        from email_verification_code
        order by email_verification_code_id
    $$,
    format(
        $$values (%L::uuid), (%L::uuid)$$,
        :'codeActiveID',
        :'codeExpiredBoundaryID'
    ),
    'Should leave remaining expired and active verification codes after the first batch'
);

-- Should delete the remaining boundary-expired code with the default batch size
select is(
    delete_expired_email_verification_codes(),
    1,
    'Should delete the remaining boundary-expired code with the default batch size'
);

-- Should leave only active verification codes after draining expired codes
select results_eq(
    $$
        select email_verification_code_id
        from email_verification_code
        order by email_verification_code_id
    $$,
    format($$values (%L::uuid)$$, :'codeActiveID'),
    'Should leave only active verification codes after draining expired codes'
);

-- Should return zero when no expired verification codes remain
select is(
    delete_expired_email_verification_codes(),
    0,
    'Should return zero when no expired verification codes remain'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
