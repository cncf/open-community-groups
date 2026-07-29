-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '3a080000-0000-0000-0000-000000000001'
\set communityID '3a080000-0000-0000-0000-000000000002'
\set eventCategoryID '3a080000-0000-0000-0000-000000000003'
\set eventID '3a080000-0000-0000-0000-000000000004'
\set groupCategoryID '3a080000-0000-0000-0000-000000000005'
\set groupID '3a080000-0000-0000-0000-000000000006'
\set invitedUserID '3a080000-0000-0000-0000-000000000007'
\set questionsInvitedUserID '3a080000-0000-0000-0000-000000000008'
\set questionsRegisteredUserID '3a080000-0000-0000-0000-000000000009'
\set unknownGroupID '3a080000-0000-0000-0000-000000000010'

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
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Tech', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'G1', 'g1');

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
values (
    :'eventID',
    'Free Event',
    'free-event',
    'Test free event',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true
);

-- Event invitation offers
insert into admission_offer (
    event_id,
    expires_at,
    source,
    status,
    user_id
) values
    (
        :'eventID',
        current_timestamp + interval '1 hour',
        'organizer_invitation',
        'pending',
        :'invitedUserID'
    ),
    (
        :'eventID',
        current_timestamp + interval '1 hour',
        'organizer_invitation',
        'pending',
        :'questionsInvitedUserID'
    );

-- Non-invitation pending registration
insert into event_attendee (event_id, user_id, manually_invited, status)
values (:'eventID', :'questionsRegisteredUserID', false, 'registration-questions-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel pending invitations.
select lives_ok(
    format(
        $$ select cancel_event_attendee_invitation(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventID', :'invitedUserID'
    ),
    'Should cancel a pending invitation'
);

select is(
    (select status from admission_offer where event_id = :'eventID' and user_id = :'invitedUserID'),
    'canceled',
    'Should persist canceled offer status'
);

select ok(
    not exists (
        select 1
        from event_attendee
        where event_id = :'eventID'
        and user_id = :'invitedUserID'
    ),
    'Should not create attendee state when canceling'
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
            details - 'admission_offer_id'
        from audit_log
    $$,
    format(
        $$
        values (
            'event_attendee_invitation_canceled',
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'user',
            jsonb_build_object('event_id', %L::uuid, 'user_id', %L::uuid)
        )
        $$,
        :'actorID', :'communityID', :'eventID', :'groupID', :'invitedUserID',
        :'eventID', :'invitedUserID'
    ),
    'Should create the expected audit row'
);

-- Should cancel manually invited attendees pending registration questions.
select lives_ok(
    format(
        $$ select cancel_event_attendee_invitation(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventID', :'questionsInvitedUserID'
    ),
    'Should cancel a manually invited attendee pending registration questions'
);

select is(
    (
        select status
        from admission_offer
        where event_id = :'eventID'
        and user_id = :'questionsInvitedUserID'
    ),
    'canceled',
    'Should persist canceled offer status for registration-question invitations'
);

select ok(
    not exists (
        select 1
        from event_attendee
        where event_id = :'eventID'
        and user_id = :'questionsInvitedUserID'
    ),
    'Should not create pending registration state when canceling'
);

-- Should reject canceling non-manual pending question registrations.
select throws_ok(
    format(
        $$ select cancel_event_attendee_invitation(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventID', :'questionsRegisteredUserID'
    ),
    'pending event invitation not found',
    'Should reject canceling non-manual pending question registrations'
);

-- Should reject canceling non-pending invitations.
select throws_ok(
    format(
        $$ select cancel_event_attendee_invitation(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventID', :'invitedUserID'
    ),
    'pending event invitation not found',
    'Should reject canceling non-pending invitations'
);

-- Should reject events outside the selected group.
select throws_ok(
    format(
        $$ select cancel_event_attendee_invitation(%L, %L, %L, %L) $$,
        :'actorID', :'unknownGroupID', :'eventID', :'invitedUserID'
    ),
    'event not found',
    'Should reject events outside the selected group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
