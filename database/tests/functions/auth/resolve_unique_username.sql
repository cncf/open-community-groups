-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set excludedUserID '0a080000-0000-0000-0000-000000000001'
\set exhaustedUsernameUserID '0a080000-0000-0000-0000-000000000002'
\set user2ID '0a080000-0000-0000-0000-000000000003'
\set user3ID '0a080000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (
    user_id,
    name,
    auth_hash,
    email,
    email_verified,
    username
) values (
    :'excludedUserID',
    'Reserved User',
    'reserved-hash',
    'reserved@example.com',
    true,
    'reserved'
), (
    :'exhaustedUsernameUserID',
    'Exhausted User',
    'exhausted-hash',
    'exhausted@example.com',
    true,
    'exhausted'
), (
    :'user2ID',
    'Taken User',
    'taken-hash',
    'taken@example.com',
    true,
    'taken'
), (
    :'user3ID',
    'Taken User 2',
    'taken-2-hash',
    'taken2@example.com',
    true,
    'taken2'
);

-- Exhausted username variants
insert into "user" (user_id, name, auth_hash, email, email_verified, username)
select
    ('0a080000-0000-0000-0000-' || lpad((100 + suffix)::text, 12, '0'))::uuid,
    format('Exhausted User %s', suffix),
    'exhausted-hash-' || suffix,
    format('exhausted%s@example.com', suffix),
    true,
    'exhausted' || suffix
from generate_series(2, 99) as suffix;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the base username when it is available
select is(
    resolve_unique_username('available'),
    'available',
    'Should return the base username when it is available'
);

-- Should append the first available numeric suffix
select is(
    resolve_unique_username('taken'),
    'taken3',
    'Should append the first available numeric suffix'
);

-- Should treat usernames as taken regardless of case
select is(
    resolve_unique_username('TAKEN'),
    'TAKEN3',
    'Should treat usernames as taken regardless of case'
);

-- Should ignore the excluded user row when resolving a username
select is(
    resolve_unique_username('reserved', :'excludedUserID'),
    'reserved',
    'Should ignore the excluded user row when resolving a username'
);

-- Should still resolve collisions outside the excluded row
select is(
    resolve_unique_username('taken', :'excludedUserID'),
    'taken3',
    'Should still resolve collisions outside the excluded row'
);

-- Should reject usernames when all generated variants are taken
select throws_ok(
    $$ select resolve_unique_username('exhausted') $$,
    'unable to generate unique username: all variants from exhausted to exhausted99 are taken',
    'Should reject usernames when all generated variants are taken'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
