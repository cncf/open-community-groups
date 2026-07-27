-- Tests public profile badge listings across communities.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'b0040000-0000-0000-0000-000000000001'
\set groupCategoryID 'b0040000-0000-0000-0000-000000000002'
\set groupID 'b0040000-0000-0000-0000-000000000003'
\set limitUserID 'b0040000-0000-0000-0000-000000000008'
\set otherCommunityID 'b0040000-0000-0000-0000-000000000009'
\set otherGroupCategoryID 'b0040000-0000-0000-0000-000000000010'
\set otherGroupID 'b0040000-0000-0000-0000-000000000011'
\set otherStatusListID 'b0040000-0000-0000-0000-000000000012'
\set statusListID 'b0040000-0000-0000-0000-000000000004'
\set userBadgeHiddenID 'b0040000-0000-0000-0000-000000000005'
\set userBadgeListedID 'b0040000-0000-0000-0000-000000000006'
\set userBadgeOtherCommunityID 'b0040000-0000-0000-0000-000000000013'
\set userID 'b0040000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User whose public badges are requested
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'profile@example.test', true, 'profile-user');

-- User whose null-limit listing proves the default public page cap
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'limitUserID', 'hash', 'limit-profile@example.test', true, 'limit-profile-user');

-- Community that contains the first issuing group
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Profile Community', '/logo', 'profile-community');

-- Community that contains the cross-community issuing group
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'otherCommunityID', '/mobile', '/banner', 'Description', 'Other Community', '/logo', 'other-community');

-- Category used by the first issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Category used by the cross-community issuing group
insert into group_category (group_category_id, community_id, name)
values (:'otherGroupCategoryID', :'otherCommunityID', 'Technology');

-- Group that issued the listed and hidden badges
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Profile Group', 'profile-group');

-- Group in the other community that issued the cross-community badge
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'otherGroupID', :'otherCommunityID', :'otherGroupCategoryID', 'Other Community Group', 'other-community-group');

-- Status list referenced by the first group's awards
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Status list referenced by the cross-community award
insert into badge_status_list (badge_status_list_id, group_id)
values (:'otherStatusListID', :'otherGroupID');

-- Listed and hidden active awards from the first community
insert into user_badge (
    user_badge_id, badge_status_list_id, display_order, group_id, is_listed, snapshot, status_list_index,
    user_id
) values
    (
        :'userBadgeListedID',
        :'statusListID',
        0,
        :'groupID',
        true,
        '{"image_file_name":"listed.png","issuer":{"community_name":"Profile Community","group_name":"Profile Group"},"name":"Listed"}',
        1,
        :'userID'
    ),
    (
        :'userBadgeHiddenID',
        :'statusListID',
        1,
        :'groupID',
        false,
        '{"image_file_name":"hidden.png","issuer":{"community_name":"Profile Community","group_name":"Profile Group"},"name":"Hidden"}',
        2,
        :'userID'
    );

-- Listed active award from the other community for the same user
insert into user_badge (
    user_badge_id, badge_status_list_id, display_order, group_id, is_listed, snapshot, status_list_index,
    user_id
) values (
    :'userBadgeOtherCommunityID',
    :'otherStatusListID',
    2,
    :'otherGroupID',
    true,
    '{"image_file_name":"other-listed.png","issuer":{"community_name":"Other Community","group_name":"Other Community Group"},"name":"Other Listed"}',
    1,
    :'userID'
);

-- Listed active awards used to prove null limits remain bounded
insert into user_badge (
    badge_status_list_id, display_order, group_id, is_listed, snapshot, status_list_index,
    user_id
)
select
    :'statusListID'::uuid,
    series.value,
    :'groupID'::uuid,
    true,
    jsonb_build_object(
        'image_file_name', format('listed-%s.png', series.value),
        'issuer', jsonb_build_object(
            'community_name', 'Profile Community',
            'group_name', 'Profile Group'
        ),
        'name', format('Listed %s', series.value)
    ),
    100 + series.value,
    :'limitUserID'::uuid
from generate_series(0, 50) as series(value);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return listed active badges across all communities
select is(
    jsonb_array_length(list_user_public_badges('PROFILE-USER')::jsonb),
    2,
    'Should return listed active badges across all communities'
);

-- Should expose only the minimal projection used by public profiles
select is(
    list_user_public_badges('profile-user')::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'snapshot', jsonb_build_object(
                'image_file_name', 'listed.png',
                'issuer', jsonb_build_object(
                    'community_name', 'Profile Community',
                    'group_name', 'Profile Group'
                ),
                'name', 'Listed'
            ),
            'user_badge_id', :'userBadgeListedID'::uuid
        ),
        jsonb_build_object(
            'snapshot', jsonb_build_object(
                'image_file_name', 'other-listed.png',
                'issuer', jsonb_build_object(
                    'community_name', 'Other Community',
                    'group_name', 'Other Community Group'
                ),
                'name', 'Other Listed'
            ),
            'user_badge_id', :'userBadgeOtherCommunityID'::uuid
        )
    ),
    'Should expose only the minimal public profile projection'
);

-- Should apply bounded pagination after stable display ordering
select is(
    list_user_public_badges('profile-user', 1, 1)::jsonb,
    jsonb_build_array(jsonb_build_object(
        'snapshot', jsonb_build_object(
            'image_file_name', 'other-listed.png',
            'issuer', jsonb_build_object(
                'community_name', 'Other Community',
                'group_name', 'Other Community Group'
            ),
            'name', 'Other Listed'
        ),
        'user_badge_id', :'userBadgeOtherCommunityID'::uuid
    )),
    'Should apply public profile pagination'
);

-- Should default a null limit to the public page-size cap
select is(
    jsonb_array_length(list_user_public_badges('limit-profile-user', null, 0)::jsonb),
    50,
    'Should default a null limit to the public page-size cap'
);

-- Should default a null offset to the first public profile page
select is(
    list_user_public_badges('profile-user', 1, null)::jsonb,
    jsonb_build_array(jsonb_build_object(
        'snapshot', jsonb_build_object(
            'image_file_name', 'listed.png',
            'issuer', jsonb_build_object(
                'community_name', 'Profile Community',
                'group_name', 'Profile Group'
            ),
            'name', 'Listed'
        ),
        'user_badge_id', :'userBadgeListedID'::uuid
    )),
    'Should default a null offset to the first public profile page'
);

-- Should reject requests above the public page-size cap
select throws_ok(
    $$select list_user_public_badges('profile-user', 51, 0)$$,
    'badge pagination is outside the supported range',
    'Should reject an unbounded public profile request'
);

-- Should return an empty list for an unknown user
select is(
    list_user_public_badges('missing')::jsonb,
    '[]'::jsonb,
    'Should return an empty list for an unknown user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
