-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(44);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set allianceID '00000000-0000-0000-0000-000000000001'
\set eventCanceled '00000000-0000-0000-0000-000000000043'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventInviteOnly '00000000-0000-0000-0000-000000000049'
\set eventDeleted '00000000-0000-0000-0000-000000000044'
\set eventFullNoWaitlist '00000000-0000-0000-0000-000000000047'
\set eventFullWaitlist '00000000-0000-0000-0000-000000000048'
\set eventInactiveGroup '00000000-0000-0000-0000-000000000045'
\set eventOK '00000000-0000-0000-0000-000000000041'
\set eventPast '00000000-0000-0000-0000-000000000046'
\set eventQuestionsApprovalID '90400000-0000-0000-0000-000000000042'
\set eventQuestionsFullWaitlistID '90400000-0000-0000-0000-000000000043'
\set eventQuestionsID '90400000-0000-0000-0000-000000000041'
\set eventUnpublished '00000000-0000-0000-0000-000000000042'
\set groupID '00000000-0000-0000-0000-000000000021'
\set inactiveGroupID '00000000-0000-0000-0000-000000000022'
\set questionsAttendeeUserID '90400000-0000-0000-0000-000000000031'
\set questionsCategoryID '90400000-0000-0000-0000-000000000011'
\set questionsAllianceID '90400000-0000-0000-0000-000000000001'
\set questionsEventCategoryID '90400000-0000-0000-0000-000000000012'
\set questionsGroupID '90400000-0000-0000-0000-000000000021'
\set questionsRequestUserID '90400000-0000-0000-0000-000000000034'
\set questionsRejoinConflictUserID '90400000-0000-0000-0000-000000000036'
\set questionsRejoinInsertUserID '90400000-0000-0000-0000-000000000035'
\set questionsSeatUserID '90400000-0000-0000-0000-000000000033'
\set questionsWaitlistUserID '90400000-0000-0000-0000-000000000032'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set user3ID '00000000-0000-0000-0000-000000000033'
\set user4ID '00000000-0000-0000-0000-000000000034'
\set user5ID '00000000-0000-0000-0000-000000000035'
\set user6ID '00000000-0000-0000-0000-000000000036'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'allianceID', 'test-alliance', 'Test Alliance', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Alliance for registration-question attendance tests
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'questionsAllianceID', 'attend-questions-alliance', 'Attend Questions Alliance', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner-mobile.png', 'https://example.com/banner.png');

-- Group category
insert into group_category (group_category_id, name, alliance_id)
values (:'categoryID', 'Technology', :'allianceID');

-- Group category for registration-question attendance tests
insert into group_category (group_category_id, name, alliance_id)
values (:'questionsCategoryID', 'Technology', :'questionsAllianceID');

-- Event category
insert into event_category (event_category_id, name, alliance_id)
values (:'eventCategoryID', 'General', :'allianceID');

-- Event category for registration-question attendance tests
insert into event_category (event_category_id, name, alliance_id)
values (:'questionsEventCategoryID', 'General', :'questionsAllianceID');

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'user1ID', 'h', 'u1@test.com', 'u1'),
    (:'user2ID', 'h', 'u2@test.com', 'u2'),
    (:'user3ID', 'h', 'u3@test.com', 'u3'),
    (:'user4ID', 'h', 'u4@test.com', 'u4'),
    (:'user5ID', 'h', 'u5@test.com', 'u5'),
    (:'user6ID', 'h', 'u6@test.com', 'u6');

-- Users that submit registration answers while attending
insert into "user" (user_id, auth_hash, email, email_verified, name, registration_status, username)
values
    (:'questionsAttendeeUserID', 'rq-hash-1', 'rq-attend@example.com', true, 'Attendee', 'registered', 'rq-attendee'),
    (:'questionsWaitlistUserID', 'rq-hash-2', 'rq-waitlist@example.com', true, 'Waitlist User', 'registered', 'rq-waitlist'),
    (:'questionsSeatUserID', 'rq-hash-3', 'rq-seat@example.com', true, 'Seat Holder', 'registered', 'rq-seat'),
    (:'questionsRequestUserID', 'rq-hash-4', 'rq-request@example.com', true, 'Requester', 'registered', 'rq-requester'),
    (:'questionsRejoinInsertUserID', 'rq-hash-5', 'rq-rejoin-insert@example.com', true, 'Rejoin Insert', 'registered', 'rq-rejoin-insert'),
    (:'questionsRejoinConflictUserID', 'rq-hash-6', 'rq-rejoin-conflict@example.com', true, 'Rejoin Conflict', 'registered', 'rq-rejoin-conflict');

-- Groups
insert into "group" (group_id, alliance_id, group_category_id, name, slug, active, deleted)
values
    (:'groupID', :'allianceID', :'categoryID', 'Active Group', 'active-group', true, false),
    (:'inactiveGroupID', :'allianceID', :'categoryID', 'Inactive Group', 'inactive-group', false, false);

-- Group for registration-question attendance tests
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'questionsGroupID', :'questionsAllianceID', :'questionsCategoryID', 'Attend Questions Group', 'attend-questions-group');

-- Events
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    canceled,
    deleted,
    starts_at,
    ends_at,
    capacity,
    waitlist_enabled,
    attendee_approval_required
)
values
    (:'eventOK', 'OK', 'ok', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, null, false, false),
    (:'eventUnpublished', 'Unpub', 'unpub', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, false, null, null, null, false, false),
    (:'eventCanceled', 'Canceled', 'canceled', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, true, false, null, null, null, false, false),
    (:'eventDeleted', 'Deleted', 'deleted', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, true, null, null, null, false, false),
    (:'eventInactiveGroup', 'Inactive Group', 'inactive-group', 'd', 'UTC', :'eventCategoryID', 'in-person', :'inactiveGroupID', true, false, false, null, null, null, false, false),
    (:'eventPast', 'Past', 'past', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, current_timestamp - interval '2 hours', current_timestamp - interval '1 hour', null, false, false),
    (:'eventFullNoWaitlist', 'Full No Waitlist', 'full-no-waitlist', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, 2, false, false),
    (:'eventFullWaitlist', 'Full Waitlist', 'full-waitlist', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, 1, true, false),
    (:'eventInviteOnly', 'Invite Only', 'invite-only', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, 1, false, true);

-- Events requiring registration answers during attendance
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    starts_at,
    capacity,
    waitlist_enabled,
    attendee_approval_required,
    registration_questions
) values (
    :'eventQuestionsID',
    :'questionsGroupID',
    'Questions Event',
    'questions-event',
    'Desc',
    'UTC',
    :'questionsEventCategoryID',
    'in-person',
    true,
    '2030-01-01 10:00:00+00',
    null,
    false,
    false,
    '[{"id": "90400000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb
), (
    :'eventQuestionsApprovalID',
    :'questionsGroupID',
    'Approval Questions Event',
    'approval-questions-event',
    'Desc',
    'UTC',
    :'questionsEventCategoryID',
    'in-person',
    true,
    '2030-01-02 10:00:00+00',
    null,
    false,
    true,
    '[{"id": "90400000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb
), (
    :'eventQuestionsFullWaitlistID',
    :'questionsGroupID',
    'Questions Full Waitlist Event',
    'questions-full-waitlist-event',
    'Desc',
    'UTC',
    :'questionsEventCategoryID',
    'in-person',
    true,
    '2030-01-03 10:00:00+00',
    1,
    true,
    false,
    '[{"id": "90400000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb
);

-- Event attendees
insert into event_attendee (event_id, user_id, status)
values
    (:'eventFullNoWaitlist', :'user1ID', 'confirmed'),
    (:'eventFullWaitlist', :'user1ID', 'confirmed'),
    (:'eventQuestionsFullWaitlistID', :'questionsSeatUserID', 'confirmed');

-- Stale canceled attendee row for accepted approval-request rejoin tests
insert into event_attendee (event_id, user_id, registration_answers, status)
values (
    :'eventQuestionsApprovalID',
    :'questionsRejoinConflictUserID',
    '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Stale answer"}]}'::jsonb,
    'invitation-canceled'
);

-- Existing organizer invitation decisions
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'eventOK', :'user3ID', true, 'invitation-canceled'),
    (:'eventFullWaitlist', :'user3ID', false, 'invitation-canceled'),
    (:'eventFullNoWaitlist', :'user5ID', true, 'invitation-pending'),
    (:'eventFullNoWaitlist', :'user6ID', true, 'invitation-rejected');

-- Event invitation requests
insert into event_invitation_request (event_id, user_id, created_at, status, reviewed_at, reviewed_by)
values
    (:'eventInviteOnly', :'user3ID', '2024-01-01 00:00:00+00', 'accepted', '2024-01-01 01:00:00+00', :'user1ID'),
    (:'eventInviteOnly', :'user4ID', '2024-01-02 00:00:00+00', 'rejected', '2024-01-02 01:00:00+00', :'user1ID'),
    (:'eventQuestionsApprovalID', :'questionsRejoinInsertUserID', '2024-01-03 00:00:00+00', 'accepted', '2024-01-03 01:00:00+00', :'user1ID'),
    (:'eventQuestionsApprovalID', :'questionsRejoinConflictUserID', '2024-01-04 00:00:00+00', 'accepted', '2024-01-04 01:00:00+00', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should register a normal attendee when capacity allows
select is(
    attend_event(:'allianceID'::uuid, :'eventOK'::uuid, :'user1ID'::uuid),
    'attendee',
    'Returns attendee when the user gets a confirmed seat'
);

-- Should create an attendee row after a successful RSVP
select ok(
    exists(
        select 1
        from event_attendee
        where event_id = :'eventOK'::uuid and user_id = :'user1ID'::uuid
        and manually_invited = false
    ),
    'Creates non-manually invited event_attendee row after confirmed RSVP'
);

-- Should discard submitted answers when the event has no registration questions
select is(
    attend_event(
        :'allianceID'::uuid,
        :'eventOK'::uuid,
        :'user4ID'::uuid,
        '{"answers": [{"question_id": "00000000-0000-0000-0000-000000009999", "value": "No question"}]}'::jsonb
    ),
    'attendee',
    'Returns attendee when questionless event receives ignored answers'
);

select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventOK'::uuid
        and user_id = :'user4ID'::uuid
    ),
    null::jsonb,
    'Does not store answers for a questionless event'
);

-- Should allow attendance for a capacity-limited event with an open seat
select is(
    attend_event(:'allianceID'::uuid, :'eventFullNoWaitlist'::uuid, :'user2ID'::uuid),
    'attendee',
    'Returns attendee when a capacity-limited event still has room'
);

-- Should reject RSVP when the event is full and waitlist is disabled
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventFullNoWaitlist', :'user3ID'
    ),
    'event has reached capacity',
    'Rejects new RSVP when the event is sold out and waitlist is disabled'
);

-- Should reject duplicate RSVP for a confirmed attendee
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventFullNoWaitlist', :'user1ID'
    ),
    'user is already attending this event',
    'Rejects duplicate RSVP for a confirmed attendee'
);

-- Should confirm a pending organizer invitation even when the event is full
select is(
    attend_event(:'allianceID'::uuid, :'eventFullNoWaitlist'::uuid, :'user5ID'::uuid),
    'attendee',
    'Returns attendee when accepting a pending organizer invitation'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventFullNoWaitlist'::uuid
        and user_id = :'user5ID'::uuid
    ),
    'confirmed',
    'Converts the pending organizer invitation into confirmed attendance'
);

select ok(
    (
        select manually_invited
        from event_attendee
        where event_id = :'eventFullNoWaitlist'::uuid
        and user_id = :'user5ID'::uuid
    ),
    'Keeps accepted organizer invitations marked as manually invited'
);

-- Should confirm a rejected organizer invitation even when the event is full
select is(
    attend_event(:'allianceID'::uuid, :'eventFullNoWaitlist'::uuid, :'user6ID'::uuid),
    'attendee',
    'Returns attendee when reversing a rejected organizer invitation'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventFullNoWaitlist'::uuid
        and user_id = :'user6ID'::uuid
    ),
    'confirmed',
    'Converts the rejected organizer invitation into confirmed attendance'
);

-- Should allow RSVP after an organizer invitation was canceled
select is(
    attend_event(:'allianceID'::uuid, :'eventOK'::uuid, :'user3ID'::uuid),
    'attendee',
    'Returns attendee after a canceled organizer invitation'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventOK'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'confirmed',
    'Converts the canceled organizer invitation into confirmed attendance'
);

select ok(
    not (
        select manually_invited
        from event_attendee
        where event_id = :'eventOK'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'Clears manually invited when a canceled invitation is reused by a normal RSVP'
);

-- Should place the user on the waitlist when the event is full and waitlist is enabled
select is(
    attend_event(:'allianceID'::uuid, :'eventFullWaitlist'::uuid, :'user2ID'::uuid),
    'waitlisted',
    'Returns waitlisted when the event is full and waitlist is enabled'
);

-- Should create a waitlist row after joining the waitlist
select ok(
    exists(
        select 1
        from event_waitlist
        where event_id = :'eventFullWaitlist'::uuid and user_id = :'user2ID'::uuid
    ),
    'Creates event_waitlist row after joining the waitlist'
);

-- Should allow waitlist join after an organizer invitation was canceled
select is(
    attend_event(:'allianceID'::uuid, :'eventFullWaitlist'::uuid, :'user3ID'::uuid),
    'waitlisted',
    'Returns waitlisted after a canceled organizer invitation for a full event'
);

select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventFullWaitlist'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'Removes the canceled organizer invitation row before waitlisting'
);

select ok(
    exists(
        select 1
        from event_waitlist
        where event_id = :'eventFullWaitlist'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'Creates waitlist row after a canceled organizer invitation'
);

-- Should allow waitlist joins without registration answers when questions exist
select is(
    attend_event(
        :'questionsAllianceID'::uuid,
        :'eventQuestionsFullWaitlistID'::uuid,
        :'questionsWaitlistUserID'::uuid
    ),
    'waitlisted',
    'Should allow waitlist joins without registration answers when questions exist'
);

-- Should create only a waitlist row for answerless waitlist joins
select is(
    (
        select jsonb_build_object(
            'attendee_exists', exists(
                select 1
                from event_attendee
                where event_id = :'eventQuestionsFullWaitlistID'::uuid
                and user_id = :'questionsWaitlistUserID'::uuid
            ),
            'waitlist_exists', exists(
                select 1
                from event_waitlist
                where event_id = :'eventQuestionsFullWaitlistID'::uuid
                and user_id = :'questionsWaitlistUserID'::uuid
            )
        )
    ),
    '{"attendee_exists":false,"waitlist_exists":true}'::jsonb,
    'Should create only a waitlist row when joining a question-enabled waitlist without answers'
);

-- Should recreate attendance when an accepted request no longer has an attendee row
select is(
    attend_event(:'allianceID'::uuid, :'eventInviteOnly'::uuid, :'user3ID'::uuid),
    'attendee',
    'Returns attendee when an accepted requester rejoins'
);

-- Should create an attendee row for an accepted requester who rejoins
select ok(
    exists(
        select 1
        from event_attendee
        where event_id = :'eventInviteOnly'::uuid and user_id = :'user3ID'::uuid
    ),
    'Creates attendee row when an accepted requester rejoins'
);

-- Should store answers when an accepted requester rejoins after cancellation
select is(
    attend_event(
        :'questionsAllianceID'::uuid,
        :'eventQuestionsApprovalID'::uuid,
        :'questionsRejoinInsertUserID'::uuid,
        '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Rejoin answer"}]}'::jsonb
    ),
    'attendee',
    'Should allow accepted requesters to rejoin question-enabled events'
);

select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventQuestionsApprovalID'::uuid
        and user_id = :'questionsRejoinInsertUserID'::uuid
    ),
    '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Rejoin answer"}]}'::jsonb,
    'Should store answers when accepted requesters rejoin after cancellation'
);

-- Should replace stale answers when an accepted requester reuses a canceled row
select is(
    attend_event(
        :'questionsAllianceID'::uuid,
        :'eventQuestionsApprovalID'::uuid,
        :'questionsRejoinConflictUserID'::uuid,
        '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Updated rejoin answer"}]}'::jsonb
    ),
    'attendee',
    'Should allow accepted requesters to reuse canceled attendee rows'
);

select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventQuestionsApprovalID'::uuid
        and user_id = :'questionsRejoinConflictUserID'::uuid
    ),
    '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Updated rejoin answer"}]}'::jsonb,
    'Should replace stale answers when accepted requesters reuse canceled attendee rows'
);

-- Should create a pending invitation request when approval is required
select is(
    attend_event(:'allianceID'::uuid, :'eventInviteOnly'::uuid, :'user2ID'::uuid),
    'pending-approval',
    'Returns pending approval when the event requires invitation review'
);

-- Should not create an attendee row before approval
select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventInviteOnly'::uuid and user_id = :'user2ID'::uuid
    ),
    'Does not create event_attendee row before invitation approval'
);

-- Should create a pending invitation request row
select ok(
    exists(
        select 1
        from event_invitation_request
        where event_id = :'eventInviteOnly'::uuid
        and user_id = :'user2ID'::uuid
        and status = 'pending'
    ),
    'Creates pending invitation request row'
);

-- Should reject duplicate invitation requests
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventInviteOnly', :'user2ID'
    ),
    'user has already requested an invitation for this event',
    'Rejects duplicate invitation requests'
);

-- Should reject users whose invitation request was rejected
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventInviteOnly', :'user4ID'
    ),
    'invitation request was rejected for this event',
    'Rejects users whose invitation request was rejected'
);

-- Should reject duplicate waitlist joins
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventFullWaitlist', :'user2ID'
    ),
    'user is already on the waiting list for this event',
    'Rejects duplicate waitlist joins'
);

-- Should reject unpublished events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventUnpublished', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects unpublished events'
);

-- Should reject canceled events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventCanceled', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects canceled events'
);

-- Should reject deleted events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventDeleted', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects deleted events'
);

-- Should reject past events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventPast', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects past events'
);

-- Should reject events from inactive groups
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventInactiveGroup', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects events from inactive groups'
);

-- Should require answers when attending an event with questions
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'questionsAllianceID', :'eventQuestionsID', :'questionsAttendeeUserID'
    ),
    'questionnaire answers are required',
    'Should require answers when attending an event with questions'
);

-- Should attend with valid registration answers
select is(
    attend_event(
        :'questionsAllianceID'::uuid,
        :'eventQuestionsID'::uuid,
        :'questionsAttendeeUserID'::uuid,
        '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Attendee answer"}]}'::jsonb
    ),
    'attendee',
    'Should attend with valid registration answers'
);

-- Should store answers submitted while attending
select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventQuestionsID'::uuid
        and user_id = :'questionsAttendeeUserID'::uuid
    ),
    '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Attendee answer"}]}'::jsonb,
    'Should store answers submitted while attending'
);

-- Should keep approval-required attendance pending and store answers on the request
select is(
    attend_event(
        :'questionsAllianceID'::uuid,
        :'eventQuestionsApprovalID'::uuid,
        :'questionsRequestUserID'::uuid,
        '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Request answer"}]}'::jsonb
    ),
    'pending-approval',
    'Should keep approval-required attendance pending and store answers on the request'
);

-- Should store answers on pending invitation requests
select is(
    (
        select registration_answers
        from event_invitation_request
        where event_id = :'eventQuestionsApprovalID'::uuid
        and user_id = :'questionsRequestUserID'::uuid
    ),
    '{"answers": [{"question_id": "90400000-0000-0000-0000-000000000101", "value": "Request answer"}]}'::jsonb,
    'Should store answers on pending invitation requests'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
