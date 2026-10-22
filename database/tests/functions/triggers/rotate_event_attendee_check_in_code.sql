-- Tests attendee check-in credential rotation on attendance confirmation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ab000000-0000-0000-0000-000000000001'
\set confirmedCheckInCode 'ab000000-0000-0000-0000-000000000008'
\set confirmedUserID 'ab000000-0000-0000-0000-000000000007'
\set eventCategoryID 'ab000000-0000-0000-0000-000000000002'
\set eventID 'ab000000-0000-0000-0000-000000000003'
\set groupCategoryID 'ab000000-0000-0000-0000-000000000004'
\set groupID 'ab000000-0000-0000-0000-000000000005'
\set pendingCheckInCode 'ab000000-0000-0000-0000-000000000009'
\set pendingUserID 'ab000000-0000-0000-0000-000000000006'
\set questionsCheckInCode 'ab000000-0000-0000-0000-00000000000a'
\set questionsUserID 'ab000000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories, users, groups and events
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'confirmedUserID');
select fx_user(:'pendingUserID');
select fx_user(:'questionsUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Confirmed attendee that stays confirmed
insert into event_attendee (check_in_code, event_id, status, user_id)
values (:'confirmedCheckInCode', :'eventID', 'confirmed', :'confirmedUserID');

-- Invitation-pending attendee that becomes confirmed
insert into event_attendee (check_in_code, event_id, status, user_id)
values (:'pendingCheckInCode', :'eventID', 'invitation-pending', :'pendingUserID');

-- Invitation-pending attendee that moves to another unconfirmed status
insert into event_attendee (check_in_code, event_id, status, user_id)
values (:'questionsCheckInCode', :'eventID', 'invitation-pending', :'questionsUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should preserve a credential when attendance moves to another unconfirmed status
update event_attendee
set status = 'registration-questions-pending'
where event_id = :'eventID'::uuid
and user_id = :'questionsUserID'::uuid;

select is(
    (
        select check_in_code
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'questionsUserID'::uuid
    ),
    :'questionsCheckInCode'::uuid,
    'Should preserve a credential when attendance moves to another unconfirmed status'
);

-- Should preserve a credential while attendance remains confirmed
update event_attendee
set status = 'confirmed'
where event_id = :'eventID'::uuid
and user_id = :'confirmedUserID'::uuid;

select is(
    (
        select check_in_code
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'confirmedUserID'::uuid
    ),
    :'confirmedCheckInCode'::uuid,
    'Should preserve a credential while attendance remains confirmed'
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
    :'pendingCheckInCode'::uuid,
    'Should rotate a credential when attendance becomes confirmed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
