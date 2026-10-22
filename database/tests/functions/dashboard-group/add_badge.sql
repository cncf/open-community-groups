-- Tests adding group badge definitions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

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
select fx_user(:'actorID', jsonb_build_object('username', 'add-badge-actor'));
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
        $$select add_badge(%L::uuid, %L::uuid, %L::uuid, '{"criteria":" Attend ","description":" Attended the event ","image_file_name":"/images/badges/badge.png","name":" Attendee "}'::jsonb)$$,
        :'actorID', :'communityID', :'groupID'
    ),
    'Should add a valid definition'
);

-- Should persist the normalized definition
select results_eq(
    $$
        select criteria, description, group_id, image_file_name, name
        from badge
    $$,
    format(
        $$ values ('Attend', 'Attended the event', %L::uuid, 'badge.png', 'Attendee') $$,
        :'groupID'
    ),
    'Should persist the normalized definition'
);

-- Should audit the definition creation for the actor
select results_eq(
    $$
        select
            al.action,
            al.actor_user_id,
            al.actor_username,
            al.community_id,
            al.created_at,
            al.details,
            al.event_id,
            al.group_id,
            al.resource_type
        from audit_log al
        join badge b on b.badge_id = al.resource_id
    $$,
    format(
        $$ values (
            'badge_added',
            %L::uuid,
            'add-badge-actor',
            %L::uuid,
            current_timestamp,
            '{"badge_name":"Attendee"}'::jsonb,
            null::uuid,
            %L::uuid,
            'badge'
        ) $$,
        :'actorID', :'communityID', :'groupID'
    ),
    'Should audit the definition creation for the actor'
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
