-- Tests resolving the users eligible to answer an event survey.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledUserID 'a5e00007-0000-0000-0000-000000000001'
\set checkedInUserID 'a5e00007-0000-0000-0000-000000000002'
\set communityID 'a5e00007-0000-0000-0000-000000000003'
\set confirmedUserID 'a5e00007-0000-0000-0000-000000000004'
\set emptyEventID 'a5e00007-0000-0000-0000-000000000005'
\set eventCategoryID 'a5e00007-0000-0000-0000-000000000006'
\set eventID 'a5e00007-0000-0000-0000-000000000007'
\set groupCategoryID 'a5e00007-0000-0000-0000-000000000008'
\set groupID 'a5e00007-0000-0000-0000-000000000009'
\set otherEventID 'a5e00007-0000-0000-0000-00000000000a'
\set otherEventUserID 'a5e00007-0000-0000-0000-00000000000b'
\set pendingUserID 'a5e00007-0000-0000-0000-00000000000c'
\set registrationPendingEventID 'a5e00007-0000-0000-0000-00000000000d'
\set registrationPendingUserID 'a5e00007-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- User whose attendance was canceled after checking in
select fx_user(:'canceledUserID');

-- Confirmed attendee who checked in
select fx_user(:'checkedInUserID');

-- Confirmed attendee who did not check in
select fx_user(:'confirmedUserID');

-- Confirmed attendee of another event
select fx_user(:'otherEventUserID');

-- Invited user who has not accepted yet
select fx_user(:'pendingUserID');

-- Attendee who has not answered the registration questions yet
select fx_user(:'registrationPendingUserID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the surveyed events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event without attendees
select fx_event(:'emptyEventID', :'groupID', :'eventCategoryID');

-- Event whose attendees are evaluated
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Other event with its own attendee
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');

-- Event whose only attendee has pending registration questions
select fx_event(:'registrationPendingEventID', :'groupID', :'eventCategoryID');

-- Canceled attendance that checked in before canceling
insert into event_attendee (event_id, user_id, checked_in, status, attendance_canceled_at)
values (:'eventID', :'canceledUserID', true, 'attendance-canceled', current_timestamp);

-- Confirmed attendee who checked in
insert into event_attendee (event_id, user_id, checked_in, status)
values (:'eventID', :'checkedInUserID', true, 'confirmed');

-- Confirmed attendee who did not check in
insert into event_attendee (event_id, user_id, checked_in, status)
values (:'eventID', :'confirmedUserID', false, 'confirmed');

-- Pending invitation
insert into event_attendee (event_id, user_id, checked_in, status)
values (:'eventID', :'pendingUserID', false, 'invitation-pending');

-- Confirmed and checked-in attendee of the other event
insert into event_attendee (event_id, user_id, checked_in, status)
values (:'otherEventID', :'otherEventUserID', true, 'confirmed');

-- Attendance waiting for registration question answers
insert into event_attendee (event_id, user_id, checked_in, status)
values (:'registrationPendingEventID', :'registrationPendingUserID', false, 'registration-questions-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude attendees with pending registration questions
select is_empty(
    format(
        $$select user_id from event_survey_eligible_users(%L::uuid, 'confirmed')$$,
        :'registrationPendingEventID'
    ),
    'Should exclude attendees with pending registration questions'
);

-- Should return checked-in confirmed attendees for the checked-in audience
select results_eq(
    format(
        $$select user_id from event_survey_eligible_users(%L::uuid, 'checked-in') order by user_id$$,
        :'eventID'
    ),
    format($$values (%L::uuid)$$, :'checkedInUserID'),
    'Should return checked-in confirmed attendees for the checked-in audience'
);

-- Should return checked-in confirmed attendees for unknown audiences
select results_eq(
    format(
        $$select user_id from event_survey_eligible_users(%L::uuid, 'everyone') order by user_id$$,
        :'eventID'
    ),
    format($$values (%L::uuid)$$, :'checkedInUserID'),
    'Should return checked-in confirmed attendees for unknown audiences'
);

-- Should return confirmed attendees for the confirmed audience
select results_eq(
    format(
        $$select user_id from event_survey_eligible_users(%L::uuid, 'confirmed') order by user_id$$,
        :'eventID'
    ),
    format($$values (%L::uuid), (%L::uuid)$$, :'checkedInUserID', :'confirmedUserID'),
    'Should return confirmed attendees for the confirmed audience'
);

-- Should return no users for events without attendees
select is_empty(
    format(
        $$select user_id from event_survey_eligible_users(%L::uuid, 'confirmed')$$,
        :'emptyEventID'
    ),
    'Should return no users for events without attendees'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
