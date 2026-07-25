-- Tests community-scoped public profile badge listings.

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
\set statusListID 'b0040000-0000-0000-0000-000000000004'
\set userBadgeHiddenID 'b0040000-0000-0000-0000-000000000005'
\set userBadgeListedID 'b0040000-0000-0000-0000-000000000006'
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

-- Community that contains the issuing group
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Profile Community', '/logo', 'profile-community');

-- Category used by the issuing group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that issued the badges
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Profile Group', 'profile-group');

-- Status list referenced by both awards
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Listed and hidden active awards
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
        '{"image_file_name":"listed.png","issuer":{"group_name":"Profile Group"},"name":"Listed"}',
        1,
        :'userID'
    ),
    (
        :'userBadgeHiddenID',
        :'statusListID',
        1,
        :'groupID',
        false,
        '{"image_file_name":"hidden.png","issuer":{"group_name":"Profile Group"},"name":"Hidden"}',
        2,
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
        'issuer', jsonb_build_object('group_name', 'Profile Group'),
        'name', format('Listed %s', series.value)
    ),
    100 + series.value,
    :'limitUserID'::uuid
from generate_series(0, 50) as series(value);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only listed active badges in the requested community
select is(
    jsonb_array_length(list_user_public_badges(:'communityID', 'PROFILE-USER')::jsonb),
    1,
    'Should return only listed active badges in the requested community'
);

-- Should expose only the minimal projection used by public profiles
select is(
    list_user_public_badges(:'communityID', 'profile-user')::jsonb,
    jsonb_build_array(jsonb_build_object(
        'snapshot', jsonb_build_object(
            'image_file_name', 'listed.png',
            'issuer', jsonb_build_object('group_name', 'Profile Group'),
            'name', 'Listed'
        ),
        'user_badge_id', :'userBadgeListedID'::uuid
    )),
    'Should expose only the minimal public profile projection'
);

-- Should apply bounded pagination after stable display ordering
select is(
    list_user_public_badges(:'communityID', 'profile-user', 50, 1)::jsonb,
    '[]'::jsonb,
    'Should apply public profile pagination'
);

-- Should default a null limit to the public page-size cap
select is(
    jsonb_array_length(list_user_public_badges(:'communityID', 'limit-profile-user', null, 0)::jsonb),
    50,
    'Should default a null limit to the public page-size cap'
);

-- Should default a null offset to the first public profile page
select is(
    list_user_public_badges(:'communityID', 'profile-user', 50, null)::jsonb,
    jsonb_build_array(jsonb_build_object(
        'snapshot', jsonb_build_object(
            'image_file_name', 'listed.png',
            'issuer', jsonb_build_object('group_name', 'Profile Group'),
            'name', 'Listed'
        ),
        'user_badge_id', :'userBadgeListedID'::uuid
    )),
    'Should default a null offset to the first public profile page'
);

-- Should reject requests above the public page-size cap
select throws_ok(
    format(
        $$select list_user_public_badges(%L::uuid, 'profile-user', 51, 0)$$,
        :'communityID'
    ),
    'badge pagination is outside the supported range',
    'Should reject an unbounded public profile request'
);

-- Should return an empty list for an unknown user
select is(
    list_user_public_badges(:'communityID', 'missing')::jsonb,
    '[]'::jsonb,
    'Should return an empty list for an unknown user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
