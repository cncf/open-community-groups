-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'
\set user3ID '00000000-0000-0000-0000-000000000013'
\set user4ID '00000000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'c1',
    'C1',
    'Community 1',
    'https://e/logo.png',
    'https://e/banner_mobile.png',
    'https://e/banner.png'
);

-- User
insert into "user" (
    user_id, auth_hash, email, name, username, email_verified
) values (
    :'user1ID', gen_random_bytes(32), 'alice@example.com', 'Alice', 'alice', true
), (
    :'user2ID', gen_random_bytes(32), 'bob@example.com', 'Bob', 'bob', true
), (
    :'user3ID', gen_random_bytes(32), 'charlie@example.com', 'Charlie', 'charlie', true
);

insert into community_team (accepted, community_id, user_id) values
    (true, :'communityID', :'user1ID'),
    (true, :'communityID', :'user2ID'),
    (false, :'communityID', :'user3ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow deleting an accepted member when another accepted member remains
select lives_ok(
    $$ select delete_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000012'::uuid) $$,
    'Should allow deleting an accepted member when another accepted member exists'
);
select results_eq(
    $$ select count(*) from community_team where community_id = '00000000-0000-0000-0000-000000000001'::uuid and user_id = '00000000-0000-0000-0000-000000000012'::uuid $$,
    $$ values (0::bigint) $$,
    'Deleted accepted membership row should be removed'
);

-- Should allow deleting a pending invitation when there is one accepted member left
select lives_ok(
    $$ select delete_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000013'::uuid) $$,
    'Should allow deleting a pending invitation with only one accepted member left'
);

-- Should block deleting the last accepted member
select throws_ok(
    $$ select delete_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000011'::uuid) $$,
    'cannot remove the last accepted community team member',
    'Should block deleting the last accepted member'
);
select results_eq(
    $$ select count(*) from community_team where community_id = '00000000-0000-0000-0000-000000000001'::uuid and user_id = '00000000-0000-0000-0000-000000000011'::uuid $$,
    $$ values (1::bigint) $$,
    'Last accepted membership row should remain after blocked delete'
);

-- Should not allow deleting when membership does not exist
select throws_ok(
    $$ select delete_community_team_member('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000014'::uuid) $$,
    'user is not a community team member',
    'Should not allow deleting when membership does not exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
