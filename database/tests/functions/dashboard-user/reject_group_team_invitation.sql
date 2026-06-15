-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a120000-0000-0000-0000-000000000001'
\set groupCategoryID '4a120000-0000-0000-0000-000000000002'
\set groupID '4a120000-0000-0000-0000-000000000003'
\set userID '4a120000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'group-invitation-community',
    'Group Invitation Community',
    'Community for testing group invitation rejection',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', gen_random_bytes(32), 'alice@example.com', true, 'alice');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Invitation Group', 'invitation-group');

-- Pending invitation
insert into group_team (group_id, user_id, role, accepted)
values (:'groupID', :'userID', 'admin', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should remove the pending group invitation
select lives_ok(
    format(
        $$
            select reject_group_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'userID',
        :'groupID'
    ),
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
    format(
        $$
            values (
                'group_team_invitation_rejected',
                %L::uuid,
                'alice',
                %L::uuid,
                %L::uuid,
                'user',
                %L::uuid
            )
        $$,
        :'userID',
        :'communityID',
        :'groupID',
        :'userID'
    ),
    'Should create the expected audit row'
);

-- Should reject a second rejection when no pending invitation exists
select throws_ok(
    format(
        $$
            select reject_group_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'userID',
        :'groupID'
    ),
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
