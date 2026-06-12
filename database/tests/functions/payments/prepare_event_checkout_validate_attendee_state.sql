-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

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
    'attendee-state-community',
    'Attendee State Community',
    'Test',
    'https://e/banner-mobile.png',
    'https://e/banner.png',
    'https://e/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (
        :'canceledUserID',
        'hash-3',
        'canceled@example.com',
        true,
        'canceled-user'
    ),
    (
        :'confirmedUserID',
        'hash-2',
        'confirmed@example.com',
        true,
        'confirmed-user'
    ),
    (
        :'invitedUserID',
        'hash-5',
        'invited@example.com',
        true,
        'invited-user'
    ),
    (
        :'newUserID',
        'hash-1',
        'new@example.com',
        true,
        'new-user'
    ),
    (
        :'pendingAnswersUserID',
        'hash-4',
        'pending@example.com',
        true,
        'pending-user'
    ),
    (
        :'rejectedUserID',
        'hash-6',
        'rejected@example.com',
        true,
        'rejected-user'
    );

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Attendee State Group',
    'attendee-state-group'
);

-- Event
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    starts_at,
    published,
    published_at
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Attendee State Event',
    'attendee-state-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    true,
    now()
);

-- Attendees covering every lifecycle state
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'eventID', :'confirmedUserID', false, 'confirmed'),
    (:'eventID', :'canceledUserID', true, 'invitation-canceled'),
    (:'eventID', :'pendingAnswersUserID', false, 'registration-questions-pending'),
    (:'eventID', :'invitedUserID', true, 'invitation-pending'),
    (:'eventID', :'rejectedUserID', true, 'invitation-rejected');

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
    'user is already attending this ticketed event',
    'Should reject confirmed attendees'
);

-- Should reject users with a pending invitation
select throws_ok(
    format($$select prepare_event_checkout_validate_attendee_state(
        %L::uuid,
        %L::uuid
    )$$, :'eventID', :'invitedUserID'),
    'user has a pending or rejected invitation for this event',
    'Should reject users with a pending invitation'
);

-- Should reject users with a rejected invitation
select throws_ok(
    format($$select prepare_event_checkout_validate_attendee_state(
        %L::uuid,
        %L::uuid
    )$$, :'eventID', :'rejectedUserID'),
    'user has a pending or rejected invitation for this event',
    'Should reject users with a rejected invitation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
