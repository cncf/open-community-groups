-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(21);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '3a130000-0000-0000-0000-000000000001'
\set canceledEventID '3a130000-0000-0000-0000-000000000002'
\set allianceID '3a130000-0000-0000-0000-000000000003'
\set confirmedAttendeeUserID '3a130000-0000-0000-0000-000000000004'
\set eventCategoryID '3a130000-0000-0000-0000-000000000005'
\set eventID '3a130000-0000-0000-0000-000000000006'
\set eventQuestionsID '3a130000-0000-0000-0000-000000000007'
\set groupCategoryID '3a130000-0000-0000-0000-000000000008'
\set groupID '3a130000-0000-0000-0000-000000000009'
\set questionsInvitedUserID '3a130000-0000-0000-0000-000000000010'
\set registeredUserID '3a130000-0000-0000-0000-000000000011'
\set registrationQuestionID '3a130000-0000-0000-0000-000000000012'
\set rejectedUserID '3a130000-0000-0000-0000-000000000013'
\set ticketedEventID '3a130000-0000-0000-0000-000000000014'
\set ticketTypeID '3a130000-0000-0000-0000-000000000015'
\set unpublishedEventID '3a130000-0000-0000-0000-000000000016'
\set unverifiedUserID '3a130000-0000-0000-0000-000000000017'
\set waitlistedUserID '3a130000-0000-0000-0000-000000000018'

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
);

-- Group category
insert into group_category (group_category_id, name, alliance_id)
values (:'groupCategoryID', 'Tech', :'allianceID');

-- Event category
insert into event_category (event_category_id, name, alliance_id)
values (:'eventCategoryID', 'General', :'allianceID');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Test Group', 'test-group');

-- Users
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values
    ('hash-actor', 'actor@example.com', true, 'Actor', :'actorID', 'actor'),
    ('hash-confirmed', 'confirmed@example.com', true, 'Confirmed', :'confirmedAttendeeUserID', 'confirmed'),
    ('hash-registered', 'registered@example.com', true, 'Registered', :'registeredUserID', 'registered'),
    ('hash-rejected', 'rejected@example.com', true, 'Rejected', :'rejectedUserID', 'rejected'),
    ('hash-unverified', 'unverified@example.com', false, 'Unverified', :'unverifiedUserID', 'unverified'),
    ('hash-waitlisted', 'waitlisted@example.com', true, 'Waitlisted', :'waitlistedUserID', 'waitlisted'),
    ('hash-rq-invited', 'rq-invited@example.com', true, 'RQ Invited', :'questionsInvitedUserID', 'rq-invited');

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
    payment_currency_code,
    published,
    canceled,
    starts_at
)
values
    (
        :'eventID',
        'Free Event',
        'free-event',
        'Test free event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'USD',
        true,
        false,
        current_timestamp + interval '1 day'
    ), (
        :'canceledEventID',
        'Canceled Event',
        'canceled-event',
        'Test canceled event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'USD',
        true,
        true,
        current_timestamp + interval '1 day'
    ), (
        :'ticketedEventID',
        'Ticketed Event',
        'ticketed-event',
        'Test ticketed event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'USD',
        true,
        false,
        current_timestamp + interval '1 day'
    ), (
        :'unpublishedEventID',
        'Unpublished Event',
        'unpublished-event',
        'Test unpublished event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'USD',
        false,
        false,
        current_timestamp + interval '1 day'
    );

-- Event with registration questions before confirmation
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    payment_currency_code,
    published,
    starts_at,
    registration_questions
)
values (
    :'eventQuestionsID',
    'Questions Event',
    'questions-event',
    'Test event with registration questions',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    current_timestamp + interval '1 day',
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'registrationQuestionID'
    )::jsonb
);

-- Ticket types
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'ticketTypeID', :'ticketedEventID', 1, 100, 'General');

-- Existing attendees and invitation decisions
insert into event_attendee (event_id, user_id, status)
values
    (:'eventID', :'confirmedAttendeeUserID', 'confirmed'),
    (:'eventID', :'rejectedUserID', 'invitation-rejected');

-- Existing waitlist entries
insert into event_waitlist (event_id, user_id)
values (:'eventID', :'waitlistedUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject invitations with both user_id and email.
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, 'registered@example.com') $$,
        :'actorID', :'groupID', :'eventID', :'registeredUserID'
    ),
    'P0001',
    'provide exactly one invite target',
    'Should reject invitations with both user_id and email'
);

-- Should invite a registered user.
select is(
    invite_event_attendee(:'actorID', :'groupID', :'eventID', :'registeredUserID', null),
    :'registeredUserID'::uuid,
    'Should return registered invitee id'
);

select results_eq(
    format(
        $$
        select status, manually_invited
        from event_attendee
        where event_id = %L::uuid
        and user_id = %L::uuid
        $$,
        :'eventID', :'registeredUserID'
    ),
    $$ values ('invitation-pending'::text, true) $$,
    'Should create a pending manual invitation for a registered user'
);

-- Should create the expected audit row for a registered user invitation.
select results_eq(
    format(
        $$
        select
            action,
            actor_user_id,
            actor_username,
            alliance_id,
            details,
            event_id,
            group_id,
            resource_id,
            resource_type
        from audit_log
        where action = 'event_attendee_invitation_sent'
        and resource_id = %L::uuid
        $$,
        :'registeredUserID'
    ),
    format(
        $$
        values (
            'event_attendee_invitation_sent',
            %L::uuid,
            'actor',
            %L::uuid,
            '{"event_id": "%s", "user_id": "%s"}'::jsonb,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'user'
        )
        $$,
        :'actorID', :'allianceID', :'eventID', :'registeredUserID', :'eventID', :'groupID', :'registeredUserID'
    ),
    'Should create the expected audit row for a registered user invitation'
);

-- Should reject re-inviting users with a pending invitation.
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null) $$,
        :'actorID', :'groupID', :'eventID', :'registeredUserID'
    ),
    'P0001',
    'user already has a pending event invitation',
    'Should reject re-inviting users with a pending invitation'
);

-- Should reject re-inviting confirmed attendees.
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null) $$,
        :'actorID', :'groupID', :'eventID', :'confirmedAttendeeUserID'
    ),
    'P0001',
    'user is already attending this event',
    'Should reject re-inviting confirmed attendees'
);

-- Should invite a waitlisted user and remove them from the waitlist.
select is(
    invite_event_attendee(:'actorID', :'groupID', :'eventID', :'waitlistedUserID', null),
    :'waitlistedUserID'::uuid,
    'Should return waitlisted invitee id'
);

select results_eq(
    format(
        $$
        select status, manually_invited
        from event_attendee
        where event_id = %L::uuid
        and user_id = %L::uuid
        $$,
        :'eventID', :'waitlistedUserID'
    ),
    $$ values ('invitation-pending'::text, true) $$,
    'Should create a pending manual invitation for a waitlisted user'
);

select is(
    (
        select count(*)
        from event_waitlist
        where event_id = :'eventID'::uuid
        and user_id = :'waitlistedUserID'::uuid
    ),
    0::bigint,
    'Should remove the invited user from the waitlist'
);

-- Should pre-register an email invitee and keep them out of normal registration state.
select ok(
    invite_event_attendee(:'actorID', :'groupID', :'eventID', null, 'new@example.com') is not null,
    'Should invite by email'
);

select is(
    (
        select registration_status
        from "user"
        where email = 'new@example.com'
    ),
    'pre-registered',
    'Should create a pre-registered user for an email invite'
);

select results_eq(
    format(
        $$
        select
            ea.checked_in,
            ea.checked_in_at is null,
            ea.manually_invited,
            ea.status,
            u.email,
            u.registration_status
        from event_attendee ea
        join "user" u using (user_id)
        where ea.event_id = %L::uuid
        and u.email = 'new@example.com'
        $$,
        :'eventID'
    ),
    $$
        values (
            false,
            true,
            true,
            'invitation-pending',
            'new@example.com',
            'pre-registered'
        )
    $$,
    'Should create a pending attendee row for an email invite'
);

-- Should reject email invites for registered users with unverified email.
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, null, 'unverified@example.com') $$,
        :'actorID', :'groupID', :'eventID'
    ),
    'P0001',
    'registered user email is not verified',
    'Should reject email invites for registered users with unverified email'
);

-- Should allow canceling and re-inviting pending invitations.
select lives_ok(
    format(
        $$ select cancel_event_attendee_invitation(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventID', :'registeredUserID'
    ),
    'Should cancel a pending invitation'
);

select lives_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null) $$,
        :'actorID', :'groupID', :'eventID', :'registeredUserID'
    ),
    'Should allow re-inviting after cancellation'
);

-- Should reject re-inviting users that rejected an organizer invitation.
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null) $$,
        :'actorID', :'groupID', :'eventID', :'rejectedUserID'
    ),
    'P0001',
    'user rejected an invitation for this event',
    'Should reject re-inviting a user that rejected an event invitation'
);

-- Should reject ticketed events.
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null) $$,
        :'actorID', :'groupID', :'ticketedEventID', :'registeredUserID'
    ),
    'P0001',
    'manual invitations are not available for ticketed events',
    'Should reject invitations for ticketed events'
);

-- Should reject unpublished events.
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null) $$,
        :'actorID', :'groupID', :'unpublishedEventID', :'registeredUserID'
    ),
    'P0001',
    'event not found or inactive',
    'Should reject unpublished events'
);

-- Should reject canceled events.
select throws_ok(
    format(
        $$ select invite_event_attendee(%L, %L, %L, %L, null) $$,
        :'actorID', :'groupID', :'canceledEventID', :'registeredUserID'
    ),
    'P0001',
    'event not found or inactive',
    'Should reject canceled events'
);

-- Should invite users into registration-questions-pending when registration questions exist
select is(
    invite_event_attendee(:'actorID'::uuid, :'groupID'::uuid, :'eventQuestionsID'::uuid, :'questionsInvitedUserID'::uuid, null),
    :'questionsInvitedUserID'::uuid,
    'Should invite users into registration-questions-pending when registration questions exist'
);

-- Should store the pending registration status for invited users
select is(
    (
        select status
        from event_attendee
        where event_id = :'eventQuestionsID'::uuid
        and user_id = :'questionsInvitedUserID'::uuid
    ),
    'registration-questions-pending',
    'Should store the pending registration status for invited users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
