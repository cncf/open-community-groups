-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set excludedUserID '00000000-0000-0000-0000-000000000001'
\set user2ID '00000000-0000-0000-0000-000000000002'
\set user3ID '00000000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Users
insert into "user" (auth_hash, email, email_verified, name, user_id, username) values
    ('hash1', 'reserved@example.com', true, 'Reserved User', :'excludedUserID', 'reserved'),
    ('hash2', 'taken@example.com', true, 'Taken User', :'user2ID', 'taken'),
    ('hash3', 'taken2@example.com', true, 'Taken User 2', :'user3ID', 'taken2');

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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
