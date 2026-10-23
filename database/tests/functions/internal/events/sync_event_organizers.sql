-- Tests synchronizing event organizers from a submitted user list.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(21);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0e9a0000-0000-0000-0000-000000000001'
\set eventClearedID '0e9a0000-0000-0000-0000-000000000002'
\set eventCategoryID '0e9a0000-0000-0000-0000-000000000003'
\set eventDuplicatesID '0e9a0000-0000-0000-0000-000000000004'
\set eventKeptID '0e9a0000-0000-0000-0000-000000000006'
\set eventMixedCaseID '0e9a0000-0000-0000-0000-000000000005'
\set eventRejectedID '0e9a0000-0000-0000-0000-000000000007'
\set eventReplacedID '0e9a0000-0000-0000-0000-000000000008'
\set groupCategoryID '0e9a0000-0000-0000-0000-000000000009'
\set formerUserID '0e9a0000-0000-0000-0000-000000000013'
\set groupID '0e9a0000-0000-0000-0000-000000000010'
\set outsiderUserID '0e9a0000-0000-0000-0000-000000000011'
\set pendingUserID '0e9a0000-0000-0000-0000-000000000014'
\set unknownUserID '0e9a0000-0000-0000-0000-000000000012'
\set user1ID '0e9a0000-0000-0000-0000-0000000000a1'
\set user2ID '0e9a0000-0000-0000-0000-0000000000a2'
\set user3ID '0e9a0000-0000-0000-0000-0000000000a3'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the organizer events
select fx_community(:'communityID');

-- Stored organizer who is no longer a member of the group team
select fx_user(:'formerUserID', jsonb_build_object('username', 'former-sync-event-organizers'));

-- User who is not a member of the group team
select fx_user(:'outsiderUserID', jsonb_build_object('username', 'outsider-sync-event-organizers'));

-- User with a pending group team invitation
select fx_user(:'pendingUserID', jsonb_build_object('username', 'pending-sync-event-organizers'));

-- First organizer candidate
select fx_user(:'user1ID', jsonb_build_object('username', 'user1-sync-event-organizers'));

-- Second organizer candidate
select fx_user(:'user2ID', jsonb_build_object('username', 'user2-sync-event-organizers'));

-- Third organizer candidate
select fx_user(:'user3ID', jsonb_build_object('username', 'user3-sync-event-organizers'));

-- Event category used by the organizer events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the organizer group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the organizer events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose organizers are cleared by an empty list
select fx_event(:'eventClearedID', :'groupID', :'eventCategoryID');

-- Event receiving duplicate organizers
select fx_event(:'eventDuplicatesID', :'groupID', :'eventCategoryID');

-- Event keeping a stored organizer who left the group team
select fx_event(:'eventKeptID', :'groupID', :'eventCategoryID');

-- Event receiving differently cased spellings of the same organizer
select fx_event(:'eventMixedCaseID', :'groupID', :'eventCategoryID');

-- Event receiving rejected payloads
select fx_event(:'eventRejectedID', :'groupID', :'eventCategoryID');

-- Event whose organizers are replaced in submitted order
select fx_event(:'eventReplacedID', :'groupID', :'eventCategoryID');

-- Accepted group team members and a pending team invitation
insert into group_team (accepted, group_id, role, user_id) values
    (false, :'groupID', 'viewer', :'pendingUserID'),
    (true, :'groupID', 'viewer', :'user1ID'),
    (true, :'groupID', 'viewer', :'user2ID'),
    (true, :'groupID', 'viewer', :'user3ID');

-- Stored organizer removed by an empty list
insert into event_organizer (event_id, user_id, "order")
values (:'eventClearedID', :'user1ID', 1);

-- Stored organizer kept after leaving the group team
insert into event_organizer (event_id, user_id, "order")
values (:'eventKeptID', :'formerUserID', 1);

-- Stored organizers replaced by the submitted list
insert into event_organizer (event_id, user_id, "order") values
    (:'eventReplacedID', :'user1ID', 1),
    (:'eventReplacedID', :'user2ID', 2);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should clear organizers when an empty list is submitted
select lives_ok(
    format(
        $$select sync_event_organizers(%L::uuid, '[]'::jsonb)$$,
        :'eventClearedID'
    ),
    'Should clear organizers when an empty list is submitted'
);
select is(
    (select count(*)::int from event_organizer where event_id = :'eventClearedID'::uuid),
    0,
    'Should leave no organizers after an empty list is submitted'
);

-- Should keep a stored organizer who left the group team
select lives_ok(
    format(
        $$select sync_event_organizers(%L::uuid, %L::jsonb)$$,
        :'eventKeptID',
        jsonb_build_array(:'user2ID', :'formerUserID')
    ),
    'Should keep a stored organizer who left the group team'
);
select results_eq(
    format(
        $$select user_id, "order" from event_organizer where event_id = %L::uuid order by "order"$$,
        :'eventKeptID'
    ),
    format(
        $$values (%L::uuid, 1), (%L::uuid, 2)$$,
        :'user2ID',
        :'formerUserID'
    ),
    'Should store the kept organizer alongside the added team member'
);

-- Should reject a JSON null payload
select throws_ok(
    format(
        $$select sync_event_organizers(%L::uuid, 'null'::jsonb)$$,
        :'eventRejectedID'
    ),
    'OCG01',
    'invalid organizers payload',
    'Should reject a JSON null payload'
);

-- Should reject a malformed UUID element
select throws_ok(
    format(
        $$select sync_event_organizers(%L::uuid, '["not-a-uuid"]'::jsonb)$$,
        :'eventRejectedID'
    ),
    'OCG01',
    'invalid organizers payload',
    'Should reject a malformed UUID element'
);

-- Should reject a null element
select throws_ok(
    format(
        $$select sync_event_organizers(%L::uuid, %L::jsonb)$$,
        :'eventRejectedID',
        jsonb_build_array(:'user2ID', null)
    ),
    'OCG01',
    'invalid organizers payload',
    'Should reject a null element'
);

-- Should reject a number element
select throws_ok(
    format(
        $$select sync_event_organizers(%L::uuid, '[1]'::jsonb)$$,
        :'eventRejectedID'
    ),
    'OCG01',
    'invalid organizers payload',
    'Should reject a number element'
);

-- Should reject a pending group team member
select throws_ok(
    format(
        $$select sync_event_organizers(%L::uuid, %L::jsonb)$$,
        :'eventRejectedID',
        jsonb_build_array(:'user2ID', :'pendingUserID')
    ),
    'OCG01',
    'organizer is not a group team member',
    'Should reject a pending group team member'
);

-- Should reject a scalar payload
select throws_ok(
    format(
        $$select sync_event_organizers(%L::uuid, %L::jsonb)$$,
        :'eventRejectedID',
        to_jsonb(:'user2ID'::text)
    ),
    'OCG01',
    'invalid organizers payload',
    'Should reject a scalar payload'
);

-- Should reject an object payload
select throws_ok(
    format(
        $$select sync_event_organizers(%L::uuid, %L::jsonb)$$,
        :'eventRejectedID',
        jsonb_build_object('user_id', :'user2ID')
    ),
    'OCG01',
    'invalid organizers payload',
    'Should reject an object payload'
);

-- Should reject an SQL NULL payload
select throws_ok(
    format(
        $$select sync_event_organizers(%L::uuid, null::jsonb)$$,
        :'eventRejectedID'
    ),
    'OCG01',
    'invalid organizers payload',
    'Should reject an SQL NULL payload'
);

-- Should reject a user outside the group team
select throws_ok(
    format(
        $$select sync_event_organizers(%L::uuid, %L::jsonb)$$,
        :'eventRejectedID',
        jsonb_build_array(:'user2ID', :'outsiderUserID')
    ),
    'OCG01',
    'organizer is not a group team member',
    'Should reject a user outside the group team'
);

-- Should reject an organizer of another event outside the group team
select throws_ok(
    format(
        $$select sync_event_organizers(%L::uuid, %L::jsonb)$$,
        :'eventRejectedID',
        jsonb_build_array(:'formerUserID')
    ),
    'OCG01',
    'organizer is not a group team member',
    'Should reject an organizer of another event outside the group team'
);

-- Should reject an unknown user
select throws_ok(
    format(
        $$select sync_event_organizers(%L::uuid, %L::jsonb)$$,
        :'eventRejectedID',
        jsonb_build_array(:'user2ID', :'unknownUserID')
    ),
    'OCG01',
    'organizer is not a group team member',
    'Should reject an unknown user'
);

-- Should remove duplicate users keeping their first position
select lives_ok(
    format(
        $$select sync_event_organizers(%L::uuid, %L::jsonb)$$,
        :'eventDuplicatesID',
        jsonb_build_array(:'user2ID', :'user1ID', :'user2ID', :'user3ID')
    ),
    'Should remove duplicate users keeping their first position'
);
select results_eq(
    format(
        $$select user_id, "order" from event_organizer where event_id = %L::uuid order by "order"$$,
        :'eventDuplicatesID'
    ),
    format(
        $$values (%L::uuid, 1), (%L::uuid, 2), (%L::uuid, 3)$$,
        :'user2ID',
        :'user1ID',
        :'user3ID'
    ),
    'Should store each duplicate user once at its first position'
);

-- Should replace existing organizers in submitted order
select lives_ok(
    format(
        $$select sync_event_organizers(%L::uuid, %L::jsonb)$$,
        :'eventReplacedID',
        jsonb_build_array(:'user3ID', :'user1ID')
    ),
    'Should replace existing organizers in submitted order'
);
select results_eq(
    format(
        $$select user_id, "order" from event_organizer where event_id = %L::uuid order by "order"$$,
        :'eventReplacedID'
    ),
    format(
        $$values (%L::uuid, 1), (%L::uuid, 2)$$,
        :'user3ID',
        :'user1ID'
    ),
    'Should number replaced organizers from one in submitted order'
);

-- Should treat differently cased UUIDs as one user
select lives_ok(
    format(
        $$select sync_event_organizers(%L::uuid, %L::jsonb)$$,
        :'eventMixedCaseID',
        jsonb_build_array(upper(:'user1ID'), :'user2ID', :'user1ID')
    ),
    'Should treat differently cased UUIDs as one user'
);
select results_eq(
    format(
        $$select user_id, "order" from event_organizer where event_id = %L::uuid order by "order"$$,
        :'eventMixedCaseID'
    ),
    format(
        $$values (%L::uuid, 1), (%L::uuid, 2)$$,
        :'user1ID',
        :'user2ID'
    ),
    'Should store differently cased UUIDs once at their first position'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
