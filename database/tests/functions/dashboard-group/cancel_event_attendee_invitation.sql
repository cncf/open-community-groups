-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000003'
\set eventCategoryID '00000000-0000-0000-0000-000000000004'
\set eventID '00000000-0000-0000-0000-000000000005'
\set groupID '00000000-0000-0000-0000-000000000006'
\set invitedUserID '00000000-0000-0000-0000-000000000007'
\set questionsInvitedUserID '00000000-0000-0000-0000-000000000008'
\set questionsRegisteredUserID '00000000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Tech', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- Users
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values
    ('hash-actor', 'actor@example.com', true, 'Actor', :'actorID', 'actor'),
    ('hash-invited', 'invited@example.com', true, 'Invited', :'invitedUserID', 'invited'),
    (
        'hash-questions-invited',
        'questions-invited@example.com',
        true,
        'Questions Invited',
        :'questionsInvitedUserID',
        'questions-invited'
    ),
    (
        'hash-questions-registered',
        'questions-registered@example.com',
        true,
        'Questions Registered',
        :'questionsRegisteredUserID',
        'questions-registered'
    );

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published
)
values (:'eventID', 'Free Event', 'free-event', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true);

-- Event invitation
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'eventID', :'invitedUserID', true, 'invitation-pending'),
    (:'eventID', :'questionsInvitedUserID', true, 'registration-questions-pending'),
    (:'eventID', :'questionsRegisteredUserID', false, 'registration-questions-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel pending invitations.
select lives_ok(
    $$ select cancel_event_attendee_invitation(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000005',
        '00000000-0000-0000-0000-000000000007'
    ) $$,
    'Should cancel a pending invitation'
);

select is(
    (select status from event_attendee where event_id = :'eventID' and user_id = :'invitedUserID'),
    'invitation-canceled',
    'Should persist canceled invitation status'
);

select ok(
    not (select manually_invited from event_attendee where event_id = :'eventID' and user_id = :'invitedUserID'),
    'Should clear the manual invitation flag when canceling'
);

-- Should create the expected audit row.
select results_eq(
    $$
        select
            action,
            actor_user_id,
            community_id,
            event_id,
            group_id,
            resource_id,
            resource_type,
            details
        from audit_log
    $$,
    $$
        values (
            'event_attendee_invitation_canceled',
            '00000000-0000-0000-0000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000003'::uuid,
            '00000000-0000-0000-0000-000000000005'::uuid,
            '00000000-0000-0000-0000-000000000006'::uuid,
            '00000000-0000-0000-0000-000000000007'::uuid,
            'user',
            '{"event_id": "00000000-0000-0000-0000-000000000005", "user_id": "00000000-0000-0000-0000-000000000007"}'::jsonb
        )
    $$,
    'Should create the expected audit row'
);

-- Should cancel manually invited attendees pending registration questions.
select lives_ok(
    $$ select cancel_event_attendee_invitation(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000005',
        '00000000-0000-0000-0000-000000000008'
    ) $$,
    'Should cancel a manually invited attendee pending registration questions'
);

select is(
    (select status from event_attendee where event_id = :'eventID' and user_id = :'questionsInvitedUserID'),
    'invitation-canceled',
    'Should persist canceled invitation status for registration questions pending invitations'
);

select ok(
    not (select manually_invited from event_attendee where event_id = :'eventID' and user_id = :'questionsInvitedUserID'),
    'Should clear the manual invitation flag for registration questions pending invitations'
);

-- Should reject canceling non-manual pending question registrations.
select throws_ok(
    $$ select cancel_event_attendee_invitation(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000005',
        '00000000-0000-0000-0000-000000000009'
    ) $$,
    'pending event invitation not found',
    'Should reject canceling non-manual pending question registrations'
);

-- Should reject canceling non-pending invitations.
select throws_ok(
    $$ select cancel_event_attendee_invitation(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000005',
        '00000000-0000-0000-0000-000000000007'
    ) $$,
    'pending event invitation not found',
    'Should reject canceling non-pending invitations'
);

-- Should reject events outside the selected group.
select throws_ok(
    $$ select cancel_event_attendee_invitation(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-999999999999',
        '00000000-0000-0000-0000-000000000005',
        '00000000-0000-0000-0000-000000000007'
    ) $$,
    'event not found',
    'Should reject events outside the selected group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
