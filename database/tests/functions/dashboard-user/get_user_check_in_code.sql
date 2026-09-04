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

-- Community that owns the event
insert into community (community_id, banner_mobile_url, banner_url, description, display_name, logo_url, name)
values (:'communityID', '/mobile', '/banner', 'Description', 'Check-In Community', '/logo', 'check-in-community');

-- Confirmed, canceled, and unregistered users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'canceledUserID', 'hash', 'canceled@example.test', true, 'check-in-canceled'),
    (:'confirmedUserID', 'hash', 'confirmed@example.test', true, 'check-in-confirmed'),
    (:'otherUserID', 'hash', 'other@example.test', true, 'check-in-other');

-- Event category used by the events
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Category used by the hosting group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group hosting the events
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Check-In Group', 'check-in-group');

-- Event with the attendee credentials
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, slug, timezone)
values (:'eventID', 'Event with attendees', :'eventCategoryID', 'virtual', :'groupID', 'Attended Event', 'attended-event', 'UTC');

-- Event without attendees
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, slug, timezone)
values (:'otherEventID', 'Event without attendees', :'eventCategoryID', 'virtual', :'groupID', 'Empty Event', 'empty-event', 'UTC');

-- Ticket tier of the attended event
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'ticketTypeID', :'eventID', 1, 10, 'General admission');

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
