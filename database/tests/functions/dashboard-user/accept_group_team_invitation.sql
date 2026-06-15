-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a030000-0000-0000-0000-000000000001'
\set groupCategoryID '4a030000-0000-0000-0000-000000000002'
\set groupID '4a030000-0000-0000-0000-000000000003'
\set user1ID '4a030000-0000-0000-0000-000000000004'

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
    'Community for testing group invitation acceptance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'user1ID', gen_random_bytes(32), 'alice@example.com', true, 'alice');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Invitation Group', 'invitation-group');

-- Pending invitation
insert into group_team (group_id, user_id, role, accepted)
values (:'groupID', :'user1ID', 'admin', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should flip accepted to true when accepting pending invite
select lives_ok(
    format(
        $$
            select accept_group_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'user1ID',
        :'groupID'
    ),
    'Should succeed for pending invite'
);
select results_eq(
    format(
        $$
            select accepted
            from group_team
            where group_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'groupID',
        :'user1ID'
    ),
    $$ values (true) $$,
    'Invite should be marked as accepted'
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
                'group_team_invitation_accepted',
                %L::uuid,
                'alice',
                %L::uuid,
                %L::uuid,
                'user',
                %L::uuid
            )
        $$,
        :'user1ID',
        :'communityID',
        :'groupID',
        :'user1ID'
    ),
    'Should create the expected audit row'
);

-- Should raise error when no pending invitation exists
select throws_ok(
    format(
        $$
            select accept_group_team_invitation(%L::uuid, %L::uuid)
        $$,
        :'user1ID',
        :'groupID'
    ),
    'no pending group invitation found',
    'Second accept should fail since invite is no longer pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
