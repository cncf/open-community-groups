-- Tests reading a user's confirmed attendance check-in credential.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledUserID 'b2110000-0000-0000-0000-000000000001'
\set checkInCode 'b2110000-0000-0000-0000-000000000002'
\set communityID 'b2110000-0000-0000-0000-000000000003'
\set confirmedUserID 'b2110000-0000-0000-0000-000000000004'
\set eventCategoryID 'b2110000-0000-0000-0000-000000000005'
\set eventID 'b2110000-0000-0000-0000-000000000006'
\set groupCategoryID 'b2110000-0000-0000-0000-000000000007'
\set groupID 'b2110000-0000-0000-0000-000000000008'
\set otherEventID 'b2110000-0000-0000-0000-000000000009'
\set otherUserID 'b2110000-0000-0000-0000-00000000000a'
\set ticketTypeID 'b2110000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'canceledUserID');
select fx_user(:'confirmedUserID');
select fx_user(:'otherUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event with the attendee credentials
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

-- Event without attendees
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

-- Ticket tier of the attended event
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('seats_total', 10));

-- Confirmed attendance holding the credential
insert into event_attendee (event_id, check_in_code, status, user_id)
values (:'eventID', :'checkInCode', 'confirmed', :'confirmedUserID');

-- Canceled attendance without a usable credential
insert into event_attendee (event_id, attendance_canceled_at, status, user_id)
values (:'eventID', current_timestamp, 'attendance-canceled', :'canceledUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return null for a canceled attendance
select is(
    get_user_check_in_code(:'eventID'::uuid, :'canceledUserID'::uuid),
    null,
    'Should return null for a canceled attendance'
);

-- Should return null for a user not attending the event
select is(
    get_user_check_in_code(:'eventID'::uuid, :'otherUserID'::uuid),
    null,
    'Should return null for a user not attending the event'
);

-- Should return null for an event the user does not attend
select is(
    get_user_check_in_code(:'otherEventID'::uuid, :'confirmedUserID'::uuid),
    null,
    'Should return null for an event the user does not attend'
);

-- Should return the credential of a confirmed attendance
select is(
    get_user_check_in_code(:'eventID'::uuid, :'confirmedUserID'::uuid),
    :'checkInCode'::uuid,
    'Should return the credential of a confirmed attendance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
