-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000002'
\set allianceID '00000000-0000-0000-0000-000000000003'
\set eventCategoryID '00000000-0000-0000-0000-000000000004'
\set eventID '00000000-0000-0000-0000-000000000005'
\set eventQuestionsID '90400000-0000-0000-0000-000000000041'
\set groupID '00000000-0000-0000-0000-000000000006'
\set questionsInvitedUserID '90400000-0000-0000-0000-000000000033'
\set registeredUserID '00000000-0000-0000-0000-000000000007'
\set rejectedUserID '00000000-0000-0000-0000-000000000010'
\set ticketedEventID '00000000-0000-0000-0000-000000000008'
\set ticketTypeID '00000000-0000-0000-0000-000000000009'
\set waitlistedUserID '00000000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'allianceID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Group category
insert into group_category (group_category_id, name, alliance_id)
values (:'categoryID', 'Tech', :'allianceID');

-- Event category
insert into event_category (event_category_id, name, alliance_id)
values (:'eventCategoryID', 'General', :'allianceID');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'categoryID', 'G1', 'g1');

-- Users
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values
    ('hash-actor', 'actor@example.com', true, 'Actor', :'actorID', 'actor'),
    ('hash-registered', 'registered@example.com', true, 'Registered', :'registeredUserID', 'registered'),
    ('hash-rejected', 'rejected@example.com', true, 'Rejected', :'rejectedUserID', 'rejected'),
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
    starts_at
)
values
    (:'eventID', 'Free Event', 'free-event', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', 'USD', true, current_timestamp + interval '1 day'),
    (:'ticketedEventID', 'Ticketed Event', 'ticketed-event', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', 'USD', true, current_timestamp + interval '1 day');

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
    'd',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    current_timestamp + interval '1 day',
    '[{"id": "90400000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb
);

-- Ticket types
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'ticketTypeID', :'ticketedEventID', 1, 100, 'General');

-- Existing invitation decisions
insert into event_attendee (event_id, user_id, status)
values (:'eventID', :'rejectedUserID', 'invitation-rejected');

-- Existing waitlist entries
insert into event_waitlist (event_id, user_id)
values (:'eventID', :'waitlistedUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should invite a registered user.
select is(
    invite_event_attendee(:'actorID', :'groupID', :'eventID', :'registeredUserID', null),
    :'registeredUserID'::uuid,
    'Should return registered invitee id'
);

select results_eq(
    $$
        select status, manually_invited
        from event_attendee
        where event_id = '00000000-0000-0000-0000-000000000005'::uuid
        and user_id = '00000000-0000-0000-0000-000000000007'::uuid
    $$,
    $$ values ('invitation-pending'::text, true) $$,
    'Should create a pending manual invitation for a registered user'
);

-- Should invite a waitlisted user and remove them from the waitlist.
select is(
    invite_event_attendee(:'actorID', :'groupID', :'eventID', :'waitlistedUserID', null),
    :'waitlistedUserID'::uuid,
    'Should return waitlisted invitee id'
);

select results_eq(
    $$
        select status, manually_invited
        from event_attendee
        where event_id = '00000000-0000-0000-0000-000000000005'::uuid
        and user_id = '00000000-0000-0000-0000-000000000011'::uuid
    $$,
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
        where ea.event_id = '00000000-0000-0000-0000-000000000005'::uuid
        and u.email = 'new@example.com'
    $$,
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

-- Should allow canceling and re-inviting pending invitations.
select lives_ok(
    $$ select cancel_event_attendee_invitation(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000005',
        '00000000-0000-0000-0000-000000000007'
    ) $$,
    'Should cancel a pending invitation'
);

select lives_ok(
    $$ select invite_event_attendee(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000005',
        '00000000-0000-0000-0000-000000000007',
        null
    ) $$,
    'Should allow re-inviting after cancellation'
);

-- Should reject re-inviting users that rejected an organizer invitation.
select throws_ok(
    $$ select invite_event_attendee(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000005',
        '00000000-0000-0000-0000-000000000010',
        null
    ) $$,
    'P0001',
    'user rejected an invitation for this event',
    'Should reject re-inviting a user that rejected an event invitation'
);

-- Should reject ticketed events.
select throws_ok(
    $$ select invite_event_attendee(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000008',
        '00000000-0000-0000-0000-000000000007',
        null
    ) $$,
    'P0001',
    'manual invitations are not available for ticketed events',
    'Should reject invitations for ticketed events'
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
