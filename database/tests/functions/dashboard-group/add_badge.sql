-- Tests adding group badge definitions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'b1020000-0000-0000-0000-000000000001'
\set communityID 'b1020000-0000-0000-0000-000000000002'
\set groupCategoryID 'b1020000-0000-0000-0000-000000000003'
\set groupID 'b1020000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Admin authorized to manage badges
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'actorID', 'hash', 'badge-admin@example.test', true, 'badge-admin');

-- Community that owns the badge
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Badge Definition Community', '/logo', 'badge-definition-community');

-- Category used by the badge group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the badge
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Badge Definition Group', 'badge-definition-group');

-- Authorized group team member
insert into group_team (group_id, accepted, role, user_id)
values (:'groupID', true, 'admin', :'actorID');

-- Artwork available to the definition
insert into badge_artwork (file_name, group_id)
values ('badge.png', :'groupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should add a valid definition
select lives_ok(
    format(
        $$select add_badge(%L::uuid, %L::uuid, %L::uuid, '{"criteria":"Attend","description":"Attended the event","image_file_name":"/images/badges/badge.png","name":"Attendee"}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID'
    ),
    'Should add a valid definition'
);

-- Should persist the normalized definition and audit it
select ok(
    exists (select 1 from badge where name = 'Attendee' and image_file_name = 'badge.png')
    and exists (
        select 1 from audit_log
        where action = 'badge_added'
        and details = '{"badge_name":"Attendee"}'::jsonb
    ),
    'Should persist the normalized definition and audit it'
);

-- Should reject artwork owned outside the group gallery
select throws_ok(
    format(
        $$select add_badge(%L::uuid, %L::uuid, %L::uuid, '{"criteria":"C","description":"D","image_file_name":"missing.png","name":"N"}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID'
    ),
    'badge artwork not found',
    'Should reject artwork owned outside the group gallery'
);

-- Should reject empty badge fields
select throws_ok(
    format(
        $$select add_badge(%L::uuid, %L::uuid, %L::uuid, '{"criteria":" ","description":"D","image_file_name":"badge.png","name":"N"}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID'
    ),
    'badge fields are invalid',
    'Should reject empty badge fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
