-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000021'
\set userID '00000000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'categoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', gen_random_bytes(32), 'alice@example.com', true, 'alice');

-- Pending invite
insert into group_team (group_id, user_id, role, accepted)
values (:'groupID', :'userID', 'admin', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should remove the pending group invitation
select lives_ok(
    $$ select reject_group_team_invitation('00000000-0000-0000-0000-000000000031'::uuid, '00000000-0000-0000-0000-000000000021'::uuid) $$,
    'Should remove the pending group invitation'
);

-- Should delete the pending group invitation row
select is(
    (
        select count(*)::int
        from group_team
        where group_id = :'groupID'::uuid
        and user_id = :'userID'::uuid
    ),
    0,
    'Should delete the pending group invitation row'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    $$
        values (
            'group_team_invitation_rejected',
            '00000000-0000-0000-0000-000000000031'::uuid,
            'alice',
            '00000000-0000-0000-0000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000021'::uuid,
            'user',
            '00000000-0000-0000-0000-000000000031'::uuid
        )
    $$,
    'Should create the expected audit row'
);

-- Should reject a second rejection when no pending invitation exists
select throws_ok(
    $$ select reject_group_team_invitation('00000000-0000-0000-0000-000000000031'::uuid, '00000000-0000-0000-0000-000000000021'::uuid) $$,
    'no pending group invitation found',
    'Should reject a second rejection when no pending invitation exists'
);

-- Should not create an audit row when the rejection fails
select is(
    (select count(*)::int from audit_log),
    1,
    'Should not create an audit row when the rejection fails'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
