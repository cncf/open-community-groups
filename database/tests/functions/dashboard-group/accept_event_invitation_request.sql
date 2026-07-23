-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(22);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '3a010000-0000-0000-0000-000000000001'
\set communityID '3a010000-0000-0000-0000-000000000002'
\set eventApprovalDisabledID '3a010000-0000-0000-0000-000000000003'
\set eventAttendeeConflictID '3a010000-0000-0000-0000-000000000004'
\set eventAttendanceCanceledID '3a010000-0000-0000-0000-000000000025'
\set eventCategoryID '3a010000-0000-0000-0000-000000000005'
\set eventFullID '3a010000-0000-0000-0000-000000000006'
\set eventID '3a010000-0000-0000-0000-000000000007'
\set eventInactiveGroupID '3a010000-0000-0000-0000-000000000008'
\set eventPastID '3a010000-0000-0000-0000-000000000009'
\set eventPendingInvitationID '3a010000-0000-0000-0000-000000000010'
\set eventQuestionsApprovalID '3a010000-0000-0000-0000-000000000011'
\set eventRegistrationOpenUntilStartID '3a010000-0000-0000-0000-000000000023'
\set eventUnpublishedID '3a010000-0000-0000-0000-000000000012'
\set groupCategoryID '3a010000-0000-0000-0000-000000000013'
\set groupID '3a010000-0000-0000-0000-000000000014'
\set inactiveGroupID '3a010000-0000-0000-0000-000000000015'
\set questionsAcceptedRequestUserID '3a010000-0000-0000-0000-000000000016'
\set registrationQuestionID '3a010000-0000-0000-0000-000000000017'
\set requesterID '3a010000-0000-0000-0000-000000000018'
\set requester2ID '3a010000-0000-0000-0000-000000000019'
\set requester3ID '3a010000-0000-0000-0000-000000000020'
\set requester4ID '3a010000-0000-0000-0000-000000000021'
\set requester5ID '3a010000-0000-0000-0000-000000000022'
\set requester6ID '3a010000-0000-0000-0000-000000000024'
\set requester7ID '3a010000-0000-0000-0000-000000000026'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
)
values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'actorID', 'h', 'actor@test.com', 'actor'),
    (:'requesterID', 'h', 'requester@test.com', 'requester'),
    (:'requester2ID', 'h', 'requester2@test.com', 'requester2'),
    (:'requester3ID', 'h', 'requester3@test.com', 'requester3'),
    (:'requester4ID', 'h', 'requester4@test.com', 'requester4'),
    (:'requester5ID', 'h', 'requester5@test.com', 'requester5'),
    (:'requester6ID', 'h', 'requester6@test.com', 'requester6'),
    (:'requester7ID', 'h', 'requester7@test.com', 'requester7'),
    (:'questionsAcceptedRequestUserID', 'h', 'rq-accepted-request@test.com', 'rq-accepted-request');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug, active)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Group', 'group', true),
    (
        :'inactiveGroupID',
        :'communityID',
        :'groupCategoryID',
        'Inactive Group',
        'inactive-group',
        false
    );

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
    capacity,
    attendee_approval_required,
    starts_at,
    ends_at,
    registration_starts_at
)
values
    (
        :'eventID',
        'Invite Event',
        'invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        2,
        true,
        null,
        null,
        null
    ),
    (
        :'eventAttendanceCanceledID',
        'Attendance Canceled Event',
        'attendance-canceled-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        true,
        null,
        null,
        null
    ),
    (
        :'eventFullID',
        'Full Invite Event',
        'full-invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        1,
        true,
        null,
        null,
        null
    ),
    (
        :'eventUnpublishedID',
        'Unpublished Invite Event',
        'unpublished-invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        null,
        true,
        null,
        null,
        null
    ),
    (
        :'eventInactiveGroupID',
        'Inactive Group Invite Event',
        'inactive-group-invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'inactiveGroupID',
        true,
        null,
        true,
        null,
        null,
        null
    ),
    (
        :'eventApprovalDisabledID',
        'Approval Disabled Event',
        'approval-disabled-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        false,
        null,
        null,
        null
    ),
    (
        :'eventPastID',
        'Past Invite Event',
        'past-invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        true,
        current_timestamp - interval '2 hours',
        current_timestamp - interval '1 hour',
        null
    ),
    (
        :'eventPendingInvitationID',
        'Pending Invitation Event',
        'pending-invitation-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        true,
        null,
        null,
        null
    ),
    (
        :'eventAttendeeConflictID',
        'Attendee Conflict Event',
        'attendee-conflict-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        true,
        null,
        null,
        null
    ),
    (
        :'eventRegistrationOpenUntilStartID',
        'Registration Open Until Start Event',
        'registration-open-until-start-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        true,
        current_timestamp - interval '1 hour',
        current_timestamp + interval '1 hour',
        current_timestamp - interval '2 hours'
    );

-- Event with registration questions used to verify answer copying on accept
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
    attendee_approval_required,
    starts_at,
    registration_questions
) values (
    :'eventQuestionsApprovalID',
    'Approval Questions Event',
    'approval-questions-event',
    'd',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true,
    true,
    '2030-01-02 10:00:00+00',
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'registrationQuestionID'
    )::jsonb
);

-- Invitation requests
insert into event_invitation_request (event_id, user_id)
values
    (:'eventID', :'requesterID'),
    (:'eventID', :'requester2ID'),
    (:'eventFullID', :'requesterID'),
    (:'eventUnpublishedID', :'requesterID'),
    (:'eventInactiveGroupID', :'requesterID'),
    (:'eventApprovalDisabledID', :'requesterID'),
    (:'eventPastID', :'requesterID'),
    (:'eventPendingInvitationID', :'requester3ID'),
    (:'eventAttendeeConflictID', :'requester4ID'),
    (:'eventAttendeeConflictID', :'requester5ID'),
    (:'eventRegistrationOpenUntilStartID', :'requester6ID'),
    (:'eventAttendanceCanceledID', :'requester7ID');

-- Invitation request with registration answers copied when accepted
insert into event_invitation_request (event_id, user_id, registration_answers)
values (
    :'eventQuestionsApprovalID',
    :'questionsAcceptedRequestUserID',
    format(
        '{"answers": [{"question_id": "%s", "value": "Accepted request answer"}]}',
        :'registrationQuestionID'
    )::jsonb
);

-- Existing attendee that fills the second event
insert into event_attendee (event_id, user_id)
values (:'eventFullID', :'requester2ID');

-- Existing canceled manual invitation row for attendee upsert reuse
insert into event_attendee (event_id, user_id, manually_invited, status)
values (:'eventID', :'requester2ID', false, 'invitation-canceled');

-- Existing pending manual invitation row for attendee upsert reuse
insert into event_attendee (event_id, user_id, manually_invited, status)
values (:'eventPendingInvitationID', :'requester3ID', true, 'invitation-pending');

-- Existing attendee rows that block accepting their pending requests
insert into event_attendee (event_id, user_id, status)
values
    (:'eventAttendeeConflictID', :'requester4ID', 'confirmed'),
    (:'eventAttendeeConflictID', :'requester5ID', 'invitation-rejected');

-- Existing canceled attendance row reactivated by accepting a new request
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values (
    current_timestamp,
    :'requester7ID',
    :'eventAttendanceCanceledID',
    'attendance-canceled',
    :'requester7ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reactivate canceled attendance when accepting a new request
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventAttendanceCanceledID', :'requester7ID'
    ),
    'Should reactivate canceled attendance when accepting a new request'
);

-- Should clear canceled attendance metadata after reactivation
select results_eq(
    format($$
        select
            attendance_canceled_at,
            attendance_canceled_by_user_id,
            status
        from event_attendee
        where event_id = %L::uuid
        and user_id = %L::uuid
    $$, :'eventAttendanceCanceledID', :'requester7ID'),
    $$ values (null::timestamptz, null::uuid, 'confirmed'::text) $$,
    'Should clear canceled attendance metadata after reactivation'
);

-- Should accept a pending invitation request
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventID', :'requesterID'
    ),
    'Should accept a pending invitation request'
);

-- Should mark the request accepted
select results_eq(
    format(
        $$
            select status, reviewed_by is not null, reviewed_at is not null
            from event_invitation_request
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'requesterID'
    ),
    $$ values ('accepted'::text, true, true) $$,
    'Should mark the request accepted'
);

-- Should create a confirmed attendee row
select ok(
    exists(
        select 1
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'requesterID'::uuid
        and manually_invited = false
    ),
    'Should create a confirmed attendee row that is not manually invited'
);

-- Should reuse a canceled manual invitation row without marking it manually invited
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventID', :'requester2ID'
    ),
    'Should accept a request with a canceled manual invitation row'
);

select results_eq(
    format(
        $$
            select status, manually_invited
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'requester2ID'
    ),
    $$ values ('confirmed'::text, false) $$,
    'Should keep reused canceled invitation request attendees not manually invited'
);

-- Should confirm an existing pending manual invitation row
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventPendingInvitationID', :'requester3ID'
    ),
    'Should accept a request with a pending manual invitation row'
);

select results_eq(
    format(
        $$
            select status, manually_invited
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventPendingInvitationID',
        :'requester3ID'
    ),
    $$ values ('confirmed'::text, true) $$,
    'Should keep reused pending invitation request attendees manually invited'
);

-- Should track the acceptance in the audit log
select results_eq(
    format(
        $$
        select
            action,
            actor_user_id,
            community_id,
            details,
            event_id,
            group_id,
            resource_id,
            resource_type
        from audit_log
        where action = 'event_invitation_request_accepted'
        and resource_id = %L::uuid
        $$,
        :'requesterID'
    ),
    format(
        $$
        values (
            'event_invitation_request_accepted',
            %L::uuid,
            %L::uuid,
            '{"event_id": "%s", "user_id": "%s"}'::jsonb,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'user'
        )
        $$,
        :'actorID', :'communityID', :'eventID', :'requesterID', :'eventID', :'groupID', :'requesterID'
    ),
    'Should track the acceptance in the audit log'
);

-- Should reject accepting when event capacity is full
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventFullID', :'requesterID'
    ),
    'event has reached capacity',
    'Should reject accepting when event capacity is full'
);

-- Should reject accepting when event is unpublished
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventUnpublishedID', :'requesterID'
    ),
    'event not found or inactive',
    'Should reject accepting when event is unpublished'
);

-- Should reject accepting when event belongs to an inactive group
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'inactiveGroupID', :'eventInactiveGroupID', :'requesterID'
    ),
    'event not found or inactive',
    'Should reject accepting when event belongs to an inactive group'
);

-- Should reject accepting when event approval is disabled
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventApprovalDisabledID', :'requesterID'
    ),
    'event not found or inactive',
    'Should reject accepting when event approval is disabled'
);

-- Should reject accepting when event is past
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventPastID', :'requesterID'
    ),
    'event not found or inactive',
    'Should reject accepting when event is past'
);

-- Should reject accepting attendee-requested invitations after an open-only registration window reaches the event start
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventRegistrationOpenUntilStartID', :'requester6ID'
    ),
    'event registration is not open',
    'Should reject accepting attendee-requested invitations after an open-only registration window reaches the event start'
);

-- Should reject accepting an already reviewed request
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventID', :'requesterID'
    ),
    'pending invitation request not found',
    'Should reject accepting an already reviewed request'
);

-- Should reject accepting when the requester is already attending
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventAttendeeConflictID', :'requester4ID'
    ),
    'user is already attending this event',
    'Should reject accepting when the requester is already attending'
);

-- Should reject accepting when the requester rejected an organizer invitation
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventAttendeeConflictID', :'requester5ID'
    ),
    'user rejected an invitation for this event',
    'Should reject accepting when the requester rejected an organizer invitation'
);

-- Should keep conflicting requests pending and attendee rows unchanged
select is(
    (
        select jsonb_build_object(
            'attendee_statuses', (
                select jsonb_agg(status order by user_id)
                from event_attendee
                where event_id = :'eventAttendeeConflictID'::uuid
            ),
            'request_statuses', (
                select jsonb_agg(status order by user_id)
                from event_invitation_request
                where event_id = :'eventAttendeeConflictID'::uuid
            )
        )
    ),
    '{"attendee_statuses": ["confirmed", "invitation-rejected"], "request_statuses": ["pending", "pending"]}'::jsonb,
    'Should keep conflicting requests pending and attendee rows unchanged'
);

-- Should accept invitation requests that include registration answers
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventQuestionsApprovalID', :'questionsAcceptedRequestUserID'
    ),
    'Should accept invitation requests that include registration answers'
);

-- Should copy request answers to the attendee row
select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventQuestionsApprovalID'::uuid
        and user_id = :'questionsAcceptedRequestUserID'::uuid
    ),
    format(
        '{"answers": [{"question_id": "%s", "value": "Accepted request answer"}]}',
        :'registrationQuestionID'
    )::jsonb,
    'Should copy request answers to the attendee row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
