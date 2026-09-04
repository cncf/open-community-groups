-- Tests validating attendee state before checkout.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledUserID '79290000-0000-0000-0000-000000000008'
\set communityID '79290000-0000-0000-0000-000000000001'
\set confirmedUserID '79290000-0000-0000-0000-000000000007'
\set eventCategoryID '79290000-0000-0000-0000-000000000002'
\set eventID '79290000-0000-0000-0000-000000000003'
\set groupCategoryID '79290000-0000-0000-0000-000000000004'
\set groupID '79290000-0000-0000-0000-000000000005'
\set invitedUserID '79290000-0000-0000-0000-000000000010'
\set newUserID '79290000-0000-0000-0000-000000000006'
\set pendingAnswersUserID '79290000-0000-0000-0000-000000000009'
\set rejectedUserID '79290000-0000-0000-0000-000000000011'
\set waitlistedUserID '79290000-0000-0000-0000-000000000012'
\set ticketTypeID '79290000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'canceledUserID');
select fx_user(:'confirmedUserID');
select fx_user(:'invitedUserID');
select fx_user(:'newUserID');
select fx_user(:'pendingAnswersUserID');
select fx_user(:'rejectedUserID');
select fx_user(:'waitlistedUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days'
));

select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('seats_total', 10));

-- Attendees covering every lifecycle state
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'eventID', :'confirmedUserID', false, 'confirmed'),
    (:'eventID', :'canceledUserID', true, 'invitation-canceled'),
    (:'eventID', :'pendingAnswersUserID', false, 'registration-questions-pending'),
    (:'eventID', :'invitedUserID', true, 'invitation-pending'),
    (:'eventID', :'rejectedUserID', true, 'invitation-rejected');

-- Existing waitlist row that must not bypass promotion
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'eventID', :'ticketTypeID', :'waitlistedUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept users without an attendee row
select lives_ok(
    format($$select prepare_event_checkout_validate_attendee_state(
        %L::uuid,
        %L::uuid
    )$$, :'eventID', :'newUserID'),
    'Should accept users without an attendee row'
);

-- Should accept users with a canceled invitation
select lives_ok(
    format($$select prepare_event_checkout_validate_attendee_state(
        %L::uuid,
        %L::uuid
    )$$, :'eventID', :'canceledUserID'),
    'Should accept users with a canceled invitation'
);

-- Should accept users with pending registration answers
select lives_ok(
    format($$select prepare_event_checkout_validate_attendee_state(
        %L::uuid,
        %L::uuid
    )$$, :'eventID', :'pendingAnswersUserID'),
    'Should accept users with pending registration answers'
);

-- Should reject confirmed attendees
select throws_ok(
    format($$select prepare_event_checkout_validate_attendee_state(
        %L::uuid,
        %L::uuid
    )$$, :'eventID', :'confirmedUserID'),
    'OCG01',
    'user is already attending this event',
    'Should reject confirmed attendees'
);

-- Should reject users with a pending invitation
select throws_ok(
    format($$select prepare_event_checkout_validate_attendee_state(
        %L::uuid,
        %L::uuid
    )$$, :'eventID', :'invitedUserID'),
    'OCG01',
    'user has a pending or rejected invitation for this event',
    'Should reject users with a pending invitation'
);

-- Should reject users with a rejected invitation
select throws_ok(
    format($$select prepare_event_checkout_validate_attendee_state(
        %L::uuid,
        %L::uuid
    )$$, :'eventID', :'rejectedUserID'),
    'OCG01',
    'user has a pending or rejected invitation for this event',
    'Should reject users with a rejected invitation'
);

-- Should reject waitlisted users
select throws_ok(
    format($$select prepare_event_checkout_validate_attendee_state(
        %L::uuid,
        %L::uuid
    )$$, :'eventID', :'waitlistedUserID'),
    'OCG01',
    'user is already on the waiting list for this event',
    'Should reject waitlisted users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
