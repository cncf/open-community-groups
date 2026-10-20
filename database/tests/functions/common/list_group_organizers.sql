-- Tests listing the accepted team members of a group in team order.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c300000-0000-0000-0000-000000000001'
\set emptyGroupID '0c300000-0000-0000-0000-000000000002'
\set groupCategoryID '0c300000-0000-0000-0000-000000000003'
\set groupID '0c300000-0000-0000-0000-000000000004'
\set orderedFirstUserID '0c300000-0000-0000-0000-00000000000a'
\set orderedSecondUserID '0c300000-0000-0000-0000-00000000000b'
\set otherGroupID '0c300000-0000-0000-0000-000000000005'
\set otherTeamUserID '0c300000-0000-0000-0000-000000000006'
\set pendingUserID '0c300000-0000-0000-0000-000000000007'
\set unorderedAdaUserID '0c300000-0000-0000-0000-000000000008'
\set unorderedZoeUserID '0c300000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the groups
select fx_community(:'communityID');

-- Team member listed first by team order, with every public profile field
select fx_user(:'orderedFirstUserID', jsonb_build_object(
    'bio', 'Group organizer',
    'bluesky_url', 'https://bsky.app/profile/first',
    'company', 'Cloud Co',
    'facebook_url', 'https://facebook.com/first',
    'github_url', 'https://github.com/first',
    'linkedin_url', 'https://linkedin.com/in/first',
    'name', 'Zed First',
    'photo_url', 'https://example.com/first.png',
    'provider', jsonb_build_object(
        'github', jsonb_build_object('id', 'gh-first', 'username', 'first-gh')
    ),
    'title', 'Lead',
    'twitter_url', 'https://twitter.com/first',
    'username', 'first-list-group-organizers',
    'website_url', 'https://first.example.com'
));

-- Team member listed second by team order
select fx_user(:'orderedSecondUserID', jsonb_build_object(
    'name', 'Amy Second',
    'username', 'second-list-group-organizers'
));

-- Accepted member of another group team
select fx_user(:'otherTeamUserID', jsonb_build_object('username', 'other-team-list-group-organizers'));

-- User with a pending team invitation
select fx_user(:'pendingUserID', jsonb_build_object('username', 'pending-list-group-organizers'));

-- Unordered team member sorted first by name
select fx_user(:'unorderedAdaUserID', jsonb_build_object(
    'name', 'Ada Unordered',
    'username', 'ada-list-group-organizers'
));

-- Unordered team member sorted last by name
select fx_user(:'unorderedZoeUserID', jsonb_build_object(
    'name', 'Zoe Unordered',
    'username', 'zoe-list-group-organizers'
));

-- Group category used by the groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group without team members
select fx_group(:'emptyGroupID', :'communityID', :'groupCategoryID');

-- Group whose team is listed
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group whose team must not leak into other listings
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Team members covering ordered, unordered, pending, and other group rows
insert into group_team (accepted, group_id, role, user_id, "order")
values
    (true, :'groupID', 'admin', :'orderedFirstUserID', 1),
    (true, :'groupID', 'viewer', :'orderedSecondUserID', 2),
    (true, :'groupID', 'viewer', :'unorderedZoeUserID', null),
    (true, :'groupID', 'viewer', :'unorderedAdaUserID', null),
    (false, :'groupID', 'viewer', :'pendingUserID', 0),
    (true, :'otherGroupID', 'viewer', :'otherTeamUserID', 0);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list accepted team members in team order, then by name
select is(
    list_group_organizers(:'groupID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'user_id', :'orderedFirstUserID'::uuid,
            'username', 'first-list-group-organizers',

            'bio', 'Group organizer',
            'bluesky_url', 'https://bsky.app/profile/first',
            'company', 'Cloud Co',
            'facebook_url', 'https://facebook.com/first',
            'github_url', 'https://github.com/first',
            'linkedin_url', 'https://linkedin.com/in/first',
            'name', 'Zed First',
            'photo_url', 'https://example.com/first.png',
            'provider', jsonb_build_object('github', jsonb_build_object('username', 'first-gh')),
            'title', 'Lead',
            'twitter_url', 'https://twitter.com/first',
            'website_url', 'https://first.example.com'
        ),
        jsonb_build_object(
            'user_id', :'orderedSecondUserID'::uuid,
            'username', 'second-list-group-organizers',

            'name', 'Amy Second'
        ),
        jsonb_build_object(
            'user_id', :'unorderedAdaUserID'::uuid,
            'username', 'ada-list-group-organizers',

            'name', 'Ada Unordered'
        ),
        jsonb_build_object(
            'user_id', :'unorderedZoeUserID'::uuid,
            'username', 'zoe-list-group-organizers',

            'name', 'Zoe Unordered'
        )
    ),
    'Should list accepted team members in team order, then by name'
);

-- Should return an empty list for a group without team members
select is(
    list_group_organizers(:'emptyGroupID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return an empty list for a group without team members'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
