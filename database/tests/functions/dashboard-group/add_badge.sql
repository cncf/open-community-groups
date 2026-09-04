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

-- Baseline community, categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'actorID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');


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
    'OCG01',
    'badge artwork not found',
    'Should reject artwork owned outside the group gallery'
);

-- Should reject empty badge fields
select throws_ok(
    format(
        $$select add_badge(%L::uuid, %L::uuid, %L::uuid, '{"criteria":" ","description":"D","image_file_name":"badge.png","name":"N"}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID'
    ),
    'OCG01',
    'badge fields are invalid',
    'Should reject empty badge fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
