-- Tests attendee check-in credential generation and confirmation rotation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ab000000-0000-0000-0000-000000000001'
\set eventCategoryID 'ab000000-0000-0000-0000-000000000002'
\set eventID 'ab000000-0000-0000-0000-000000000003'
\set groupCategoryID 'ab000000-0000-0000-0000-000000000004'
\set groupID 'ab000000-0000-0000-0000-000000000005'
\set pendingUserID 'ab000000-0000-0000-0000-000000000006'
\set secondUserID 'ab000000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories, users, groups and events
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'pendingUserID');
select fx_user(:'secondUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Pending and confirmed attendees with generated credentials
insert into event_attendee (event_id, user_id, status) values
    (:'eventID', :'pendingUserID', 'invitation-pending'),
    (:'eventID', :'secondUserID', 'confirmed');

-- Capture the pending attendee's original credential
select check_in_code as "checkInCode"
from event_attendee
where event_id = :'eventID'::uuid
and user_id = :'pendingUserID'::uuid \gset original_

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should generate globally unique attendee credentials
select is(
    (
        select count(distinct check_in_code)::int
        from event_attendee
        where event_id = :'eventID'::uuid
    ),
    2,
    'Should generate globally unique attendee credentials'
);

-- Should rotate a credential when attendance becomes confirmed
update event_attendee
set status = 'confirmed'
where event_id = :'eventID'::uuid
and user_id = :'pendingUserID'::uuid;

select isnt(
    (
        select check_in_code
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'pendingUserID'::uuid
    ),
    :'original_checkInCode'::uuid,
    'Should rotate a credential when attendance becomes confirmed'
);

-- Capture the rotated credential before a stable-status update
select check_in_code as "checkInCode"
from event_attendee
where event_id = :'eventID'::uuid
and user_id = :'pendingUserID'::uuid \gset rotated_

-- Should preserve a credential while attendance remains confirmed
update event_attendee
set status = 'confirmed'
where event_id = :'eventID'::uuid
and user_id = :'pendingUserID'::uuid;

select is(
    (
        select check_in_code
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'pendingUserID'::uuid
    ),
    :'rotated_checkInCode'::uuid,
    'Should preserve a credential while attendance remains confirmed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
