-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(47);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '5e020000-0000-0000-0000-000000000001'
\set eventCanceledID '5e020000-0000-0000-0000-000000000002'
\set eventCategoryID '5e020000-0000-0000-0000-000000000003'
\set eventDeletedID '5e020000-0000-0000-0000-000000000004'
\set eventFullNoWaitlistID '5e020000-0000-0000-0000-000000000005'
\set eventFullWaitlistID '5e020000-0000-0000-0000-000000000006'
\set eventInactiveGroupID '5e020000-0000-0000-0000-000000000007'
\set eventInviteOnlyID '5e020000-0000-0000-0000-000000000008'
\set eventOKID '5e020000-0000-0000-0000-000000000009'
\set eventPastID '5e020000-0000-0000-0000-00000000000a'
\set eventQuestionsApprovalID '5e020000-0000-0000-0000-00000000000b'
\set eventQuestionsFullWaitlistID '5e020000-0000-0000-0000-00000000000c'
\set eventQuestionsID '5e020000-0000-0000-0000-00000000000d'
\set eventUnpublishedID '5e020000-0000-0000-0000-00000000000e'
\set groupCategoryID '5e020000-0000-0000-0000-00000000000f'
\set groupID '5e020000-0000-0000-0000-000000000010'
\set ignoredQuestionID '5e020000-0000-0000-0000-000000000011'
\set inactiveGroupID '5e020000-0000-0000-0000-000000000012'
\set questionID '5e020000-0000-0000-0000-000000000013'
\set questionsAttendeeUserID '5e020000-0000-0000-0000-000000000014'
\set questionsAllianceID '5e020000-0000-0000-0000-000000000015'
\set questionsEventCategoryID '5e020000-0000-0000-0000-000000000016'
\set questionsGroupCategoryID '5e020000-0000-0000-0000-000000000017'
\set questionsGroupID '5e020000-0000-0000-0000-000000000018'
\set questionsPendingUserID '5e020000-0000-0000-0000-000000000019'
\set questionsRejoinConflictUserID '5e020000-0000-0000-0000-00000000001a'
\set questionsRejoinInsertUserID '5e020000-0000-0000-0000-00000000001b'
\set questionsRequestUserID '5e020000-0000-0000-0000-00000000001c'
\set questionsSeatUserID '5e020000-0000-0000-0000-00000000001d'
\set questionsWaitlistUserID '5e020000-0000-0000-0000-00000000001e'
\set user1ID '5e020000-0000-0000-0000-00000000001f'
\set user2ID '5e020000-0000-0000-0000-000000000020'
\set user3ID '5e020000-0000-0000-0000-000000000021'
\set user4ID '5e020000-0000-0000-0000-000000000022'
\set user5ID '5e020000-0000-0000-0000-000000000023'
\set user6ID '5e020000-0000-0000-0000-000000000024'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'test-alliance',
    'Test Alliance',
    'A test alliance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
), (
    :'questionsAllianceID',
    'attend-questions-alliance',
    'Attend Questions Alliance',
    'Alliance for registration-question attendance tests',
    'https://example.com/questions-banner-mobile.png',
    'https://example.com/questions-banner.png',
    'https://example.com/questions-logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values
    (:'groupCategoryID', :'allianceID', 'Technology'),
    (:'questionsGroupCategoryID', :'questionsAllianceID', 'Technology');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values
    (:'eventCategoryID', :'allianceID', 'General'),
    (:'questionsEventCategoryID', :'questionsAllianceID', 'General');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name,
    registration_status
) values (
    :'user1ID',
    'user-1-hash',
    'user-1@example.com',
    true,
    'user-1',
    'User One',
    'registered'
), (
    :'user2ID',
    'user-2-hash',
    'user-2@example.com',
    true,
    'user-2',
    'User Two',
    'registered'
), (
    :'user3ID',
    'user-3-hash',
    'user-3@example.com',
    true,
    'user-3',
    'User Three',
    'registered'
), (
    :'user4ID',
    'user-4-hash',
    'user-4@example.com',
    true,
    'user-4',
    'User Four',
    'registered'
), (
    :'user5ID',
    'user-5-hash',
    'user-5@example.com',
    true,
    'user-5',
    'User Five',
    'registered'
), (
    :'user6ID',
    'user-6-hash',
    'user-6@example.com',
    true,
    'user-6',
    'User Six',
    'registered'
), (
    :'questionsAttendeeUserID',
    'rq-hash-1',
    'rq-attend@example.com',
    true,
    'rq-attendee',
    'Attendee',
    'registered'
), (
    :'questionsWaitlistUserID',
    'rq-hash-2',
    'rq-waitlist@example.com',
    true,
    'rq-waitlist',
    'Waitlist User',
    'registered'
), (
    :'questionsSeatUserID',
    'rq-hash-3',
    'rq-seat@example.com',
    true,
    'rq-seat',
    'Seat Holder',
    'registered'
), (
    :'questionsRequestUserID',
    'rq-hash-4',
    'rq-request@example.com',
    true,
    'rq-requester',
    'Requester',
    'registered'
), (
    :'questionsRejoinInsertUserID',
    'rq-hash-5',
    'rq-rejoin-insert@example.com',
    true,
    'rq-rejoin-insert',
    'Rejoin Insert',
    'registered'
), (
    :'questionsRejoinConflictUserID',
    'rq-hash-6',
    'rq-rejoin-conflict@example.com',
    true,
    'rq-rejoin-conflict',
    'Rejoin Conflict',
    'registered'
), (
    :'questionsPendingUserID',
    'rq-hash-7',
    'rq-pending@example.com',
    true,
    'rq-pending',
    'Pending Answers',
    'registered'
);

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    active,
    deleted
) values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Active Group',
    'active-group',
    true,
    false
), (
    :'inactiveGroupID',
    :'allianceID',
    :'groupCategoryID',
    'Inactive Group',
    'inactive-group',
    false,
    false
), (
    :'questionsGroupID',
    :'questionsAllianceID',
    :'questionsGroupCategoryID',
    'Attend Questions Group',
    'attend-questions-group',
    true,
    false
);

-- Events
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    attendee_approval_required,
    canceled,
    capacity,
    deleted,
    description,
    ends_at,
    published,
    starts_at,
    timezone,
    waitlist_enabled
)
values
    (
        :'eventOKID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'OK',
        'ok',
        false,
        false,
        null,
        false,
        'Test event',
        null,
        true,
        null,
        'UTC',
        false
    ),
    (
        :'eventUnpublishedID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Unpublished',
        'unpublished',
        false,
        false,
        null,
        false,
        'Test event',
        null,
        false,
        null,
        'UTC',
        false
    ),
    (
        :'eventCanceledID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Canceled',
        'canceled',
        false,
        true,
        null,
        false,
        'Test event',
        null,
        false,
        null,
        'UTC',
        false
    ),
    (
        :'eventDeletedID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Deleted',
        'deleted',
        false,
        false,
        null,
        true,
        'Test event',
        null,
        false,
        null,
        'UTC',
        false
    ),
    (
        :'eventInactiveGroupID',
        :'eventCategoryID',
        'in-person',
        :'inactiveGroupID',
        'Inactive Group',
        'inactive-group',
        false,
        false,
        null,
        false,
        'Test event',
        null,
        true,
        null,
        'UTC',
        false
    ),
    (
        :'eventPastID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Past',
        'past',
        false,
        false,
        null,
        false,
        'Past event',
        current_timestamp - interval '1 hour',
        true,
        current_timestamp - interval '2 hours',
        'UTC',
        false
    ),
    (
        :'eventFullNoWaitlistID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Full No Waitlist',
        'full-no-waitlist',
        false,
        false,
        2,
        false,
        'Full event',
        null,
        true,
        null,
        'UTC',
        false
    ),
    (
        :'eventFullWaitlistID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Full Waitlist',
        'full-waitlist',
        false,
        false,
        1,
        false,
        'Waitlist event',
        null,
        true,
        null,
        'UTC',
        true
    ),
    (
        :'eventInviteOnlyID',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Invite Only',
        'invite-only',
        true,
        false,
        1,
        false,
        'Invite-only event',
        null,
        true,
        null,
        'UTC',
        false
    );

-- Events requiring registration answers during attendance
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    attendee_approval_required,
    capacity,
    description,
    published,
    registration_questions,
    starts_at,
    timezone,
    waitlist_enabled
) values (
    :'eventQuestionsID',
    :'questionsEventCategoryID',
    'in-person',
    :'questionsGroupID',
    'Questions Event',
    'questions-event',
    false,
    null,
    'Event requiring registration answers',
    true,
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    '2030-01-01 10:00:00+00',
    'UTC',
    false
), (
    :'eventQuestionsApprovalID',
    :'questionsEventCategoryID',
    'in-person',
    :'questionsGroupID',
    'Approval Questions Event',
    'approval-questions-event',
    true,
    null,
    'Approval-required event with registration answers',
    true,
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    '2030-01-02 10:00:00+00',
    'UTC',
    false
), (
    :'eventQuestionsFullWaitlistID',
    :'questionsEventCategoryID',
    'in-person',
    :'questionsGroupID',
    'Questions Full Waitlist Event',
    'questions-full-waitlist-event',
    false,
    1,
    'Full waitlist event with registration answers',
    true,
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    '2030-01-03 10:00:00+00',
    'UTC',
    true
);

-- Event attendees
insert into event_attendee (event_id, user_id, status)
values
    (:'eventFullNoWaitlistID', :'user1ID', 'confirmed'),
    (:'eventFullWaitlistID', :'user1ID', 'confirmed'),
    (:'eventQuestionsFullWaitlistID', :'questionsSeatUserID', 'confirmed'),
    (:'eventQuestionsID', :'questionsPendingUserID', 'registration-questions-pending');

-- Stale canceled attendee row for accepted approval-request rejoin tests
insert into event_attendee (event_id, user_id, registration_answers, status)
values (
    :'eventQuestionsApprovalID',
    :'questionsRejoinConflictUserID',
    format(
        '{"answers": [{"question_id": "%s", "value": "Stale answer"}]}',
        :'questionID'
    )::jsonb,
    'invitation-canceled'
);

-- Existing organizer invitation decisions
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'eventOKID', :'user3ID', true, 'invitation-canceled'),
    (:'eventFullWaitlistID', :'user3ID', false, 'invitation-canceled'),
    (:'eventFullNoWaitlistID', :'user5ID', true, 'invitation-pending'),
    (:'eventFullNoWaitlistID', :'user6ID', true, 'invitation-rejected');

-- Event invitation requests
insert into event_invitation_request (
    event_id,
    user_id,
    created_at,
    status,
    reviewed_at,
    reviewed_by
)
values
    (
        :'eventInviteOnlyID',
        :'user3ID',
        '2024-01-01 00:00:00+00',
        'accepted',
        '2024-01-01 01:00:00+00',
        :'user1ID'
    ),
    (
        :'eventInviteOnlyID',
        :'user4ID',
        '2024-01-02 00:00:00+00',
        'rejected',
        '2024-01-02 01:00:00+00',
        :'user1ID'
    ),
    (
        :'eventQuestionsApprovalID',
        :'questionsRejoinInsertUserID',
        '2024-01-03 00:00:00+00',
        'accepted',
        '2024-01-03 01:00:00+00',
        :'user1ID'
    ),
    (
        :'eventQuestionsApprovalID',
        :'questionsRejoinConflictUserID',
        '2024-01-04 00:00:00+00',
        'accepted',
        '2024-01-04 01:00:00+00',
        :'user1ID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should register a normal attendee when capacity allows
select is(
    attend_event(:'allianceID'::uuid, :'eventOKID'::uuid, :'user1ID'::uuid),
    'attendee',
    'Returns attendee when the user gets a confirmed seat'
);

-- Should create an attendee row after a successful RSVP
select ok(
    exists(
        select 1
        from event_attendee
        where event_id = :'eventOKID'::uuid and user_id = :'user1ID'::uuid
        and manually_invited = false
    ),
    'Creates non-manually invited event_attendee row after confirmed RSVP'
);

-- Should discard submitted answers when the event has no registration questions
select is(
    attend_event(
        :'allianceID'::uuid,
        :'eventOKID'::uuid,
        :'user4ID'::uuid,
        format(
            '{"answers": [{"question_id": "%s", "value": "No question"}]}',
            :'ignoredQuestionID'
        )::jsonb
    ),
    'attendee',
    'Returns attendee when questionless event receives ignored answers'
);

select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventOKID'::uuid
        and user_id = :'user4ID'::uuid
    ),
    null::jsonb,
    'Does not store answers for a questionless event'
);

-- Should allow attendance for a capacity-limited event with an open seat
select is(
    attend_event(:'allianceID'::uuid, :'eventFullNoWaitlistID'::uuid, :'user2ID'::uuid),
    'attendee',
    'Returns attendee when a capacity-limited event still has room'
);

-- Should reject RSVP when the event is full and waitlist is disabled
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventFullNoWaitlistID', :'user3ID'
    ),
    'event has reached capacity',
    'Rejects new RSVP when the event is sold out and waitlist is disabled'
);

-- Should reject duplicate RSVP for a confirmed attendee
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventFullNoWaitlistID', :'user1ID'
    ),
    'user is already attending this event',
    'Rejects duplicate RSVP for a confirmed attendee'
);

-- Should confirm a pending organizer invitation even when the event is full
select is(
    attend_event(:'allianceID'::uuid, :'eventFullNoWaitlistID'::uuid, :'user5ID'::uuid),
    'attendee',
    'Returns attendee when accepting a pending organizer invitation'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventFullNoWaitlistID'::uuid
        and user_id = :'user5ID'::uuid
    ),
    'confirmed',
    'Converts the pending organizer invitation into confirmed attendance'
);

select ok(
    (
        select manually_invited
        from event_attendee
        where event_id = :'eventFullNoWaitlistID'::uuid
        and user_id = :'user5ID'::uuid
    ),
    'Keeps accepted organizer invitations marked as manually invited'
);

-- Should confirm a rejected organizer invitation even when the event is full
select is(
    attend_event(:'allianceID'::uuid, :'eventFullNoWaitlistID'::uuid, :'user6ID'::uuid),
    'attendee',
    'Returns attendee when reversing a rejected organizer invitation'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventFullNoWaitlistID'::uuid
        and user_id = :'user6ID'::uuid
    ),
    'confirmed',
    'Converts the rejected organizer invitation into confirmed attendance'
);

-- Should allow RSVP after an organizer invitation was canceled
select is(
    attend_event(:'allianceID'::uuid, :'eventOKID'::uuid, :'user3ID'::uuid),
    'attendee',
    'Returns attendee after a canceled organizer invitation'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventOKID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'confirmed',
    'Converts the canceled organizer invitation into confirmed attendance'
);

select ok(
    not (
        select manually_invited
        from event_attendee
        where event_id = :'eventOKID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'Clears manually invited when a canceled invitation is reused by a normal RSVP'
);

-- Should place the user on the waitlist when the event is full and waitlist is enabled
select is(
    attend_event(:'allianceID'::uuid, :'eventFullWaitlistID'::uuid, :'user2ID'::uuid),
    'waitlisted',
    'Returns waitlisted when the event is full and waitlist is enabled'
);

-- Should create a waitlist row after joining the waitlist
select ok(
    exists(
        select 1
        from event_waitlist
        where event_id = :'eventFullWaitlistID'::uuid and user_id = :'user2ID'::uuid
    ),
    'Creates event_waitlist row after joining the waitlist'
);

-- Should allow waitlist join after an organizer invitation was canceled
select is(
    attend_event(:'allianceID'::uuid, :'eventFullWaitlistID'::uuid, :'user3ID'::uuid),
    'waitlisted',
    'Returns waitlisted after a canceled organizer invitation for a full event'
);

select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventFullWaitlistID'::uuid
        and user_id = :'user3ID'::uuid
    ),
    'Removes the canceled organizer invitation row before waitlisting'
);

select ok(
    exists(
        select 1
        from event_waitlist
        where event_id = :'eventFullWaitlistID'::uuid
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
    attend_event(:'allianceID'::uuid, :'eventInviteOnlyID'::uuid, :'user3ID'::uuid),
    'attendee',
    'Returns attendee when an accepted requester rejoins'
);

-- Should create an attendee row for an accepted requester who rejoins
select ok(
    exists(
        select 1
        from event_attendee
        where event_id = :'eventInviteOnlyID'::uuid and user_id = :'user3ID'::uuid
    ),
    'Creates attendee row when an accepted requester rejoins'
);

-- Should store answers when an accepted requester rejoins after cancellation
select is(
    attend_event(
        :'questionsAllianceID'::uuid,
        :'eventQuestionsApprovalID'::uuid,
        :'questionsRejoinInsertUserID'::uuid,
        format(
            '{"answers": [{"question_id": "%s", "value": "Rejoin answer"}]}',
            :'questionID'
        )::jsonb
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
    format(
        '{"answers": [{"question_id": "%s", "value": "Rejoin answer"}]}',
        :'questionID'
    )::jsonb,
    'Should store answers when accepted requesters rejoin after cancellation'
);

-- Should replace stale answers when an accepted requester reuses a canceled row
select is(
    attend_event(
        :'questionsAllianceID'::uuid,
        :'eventQuestionsApprovalID'::uuid,
        :'questionsRejoinConflictUserID'::uuid,
        format(
            '{"answers": [{"question_id": "%s", "value": "Updated rejoin answer"}]}',
            :'questionID'
        )::jsonb
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
    format(
        '{"answers": [{"question_id": "%s", "value": "Updated rejoin answer"}]}',
        :'questionID'
    )::jsonb,
    'Should replace stale answers when accepted requesters reuse canceled attendee rows'
);

-- Should create a pending invitation request when approval is required
select is(
    attend_event(:'allianceID'::uuid, :'eventInviteOnlyID'::uuid, :'user2ID'::uuid),
    'pending-approval',
    'Returns pending approval when the event requires invitation review'
);

-- Should not create an attendee row before approval
select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventInviteOnlyID'::uuid and user_id = :'user2ID'::uuid
    ),
    'Does not create event_attendee row before invitation approval'
);

-- Should create a pending invitation request row
select ok(
    exists(
        select 1
        from event_invitation_request
        where event_id = :'eventInviteOnlyID'::uuid
        and user_id = :'user2ID'::uuid
        and status = 'pending'
    ),
    'Creates pending invitation request row'
);

-- Should reject duplicate invitation requests
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventInviteOnlyID', :'user2ID'
    ),
    'user has already requested an invitation for this event',
    'Rejects duplicate invitation requests'
);

-- Should reject users whose invitation request was rejected
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventInviteOnlyID', :'user4ID'
    ),
    'invitation request was rejected for this event',
    'Rejects users whose invitation request was rejected'
);

-- Should reject duplicate waitlist joins
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventFullWaitlistID', :'user2ID'
    ),
    'user is already on the waiting list for this event',
    'Rejects duplicate waitlist joins'
);

-- Should reject unpublished events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventUnpublishedID', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects unpublished events'
);

-- Should reject canceled events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventCanceledID', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects canceled events'
);

-- Should reject deleted events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventDeletedID', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects deleted events'
);

-- Should reject past events
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventPastID', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects past events'
);

-- Should reject events from inactive groups
select throws_ok(
    format(
        'select attend_event(%L::uuid,%L::uuid,%L::uuid)',
        :'allianceID', :'eventInactiveGroupID', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects events from inactive groups'
);

-- Should start registration-question completion from a pending attendee
select is(
    (
        select status
        from event_attendee
        where event_id = :'eventQuestionsID'::uuid
        and user_id = :'questionsPendingUserID'::uuid
    ),
    'registration-questions-pending',
    'Should start registration-question completion from a pending attendee'
);

-- Should confirm pending registration-question attendees with valid answers
select is(
    attend_event(
        :'questionsAllianceID'::uuid,
        :'eventQuestionsID'::uuid,
        :'questionsPendingUserID'::uuid,
        format(
            '{"answers": [{"question_id": "%s", "value": "Pending answer"}]}',
            :'questionID'
        )::jsonb
    ),
    'attendee',
    'Should confirm pending registration-question attendees with valid answers'
);

-- Should store answers when confirming pending registration-question attendees
select is(
    (
        select jsonb_build_object(
            'registration_answers',
            registration_answers,
            'status',
            status
        )
        from event_attendee
        where event_id = :'eventQuestionsID'::uuid
        and user_id = :'questionsPendingUserID'::uuid
    ),
    format(
        '{"registration_answers":{"answers":[{"question_id":"%s","value":"Pending answer"}]},"status":"confirmed"}',
        :'questionID'
    )::jsonb,
    'Should store answers when confirming pending registration-question attendees'
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
        format(
            '{"answers": [{"question_id": "%s", "value": "Attendee answer"}]}',
            :'questionID'
        )::jsonb
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
    format(
        '{"answers": [{"question_id": "%s", "value": "Attendee answer"}]}',
        :'questionID'
    )::jsonb,
    'Should store answers submitted while attending'
);

-- Should keep approval-required attendance pending and store answers on the request
select is(
    attend_event(
        :'questionsAllianceID'::uuid,
        :'eventQuestionsApprovalID'::uuid,
        :'questionsRequestUserID'::uuid,
        format(
            '{"answers": [{"question_id": "%s", "value": "Request answer"}]}',
            :'questionID'
        )::jsonb
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
    format(
        '{"answers": [{"question_id": "%s", "value": "Request answer"}]}',
        :'questionID'
    )::jsonb,
    'Should store answers on pending invitation requests'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
