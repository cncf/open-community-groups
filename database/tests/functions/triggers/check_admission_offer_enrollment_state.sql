-- Tests active admission offer enrollment exclusivity.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendeeUserID 'ab150000-0000-0000-0000-000000000001'
\set communityID 'ab150000-0000-0000-0000-000000000002'
\set eventCategoryID 'ab150000-0000-0000-0000-000000000003'
\set eventID 'ab150000-0000-0000-0000-000000000004'
\set groupCategoryID 'ab150000-0000-0000-0000-000000000005'
\set groupID 'ab150000-0000-0000-0000-000000000006'
\set purchaseUserID 'ab150000-0000-0000-0000-000000000007'
\set requestUserID 'ab150000-0000-0000-0000-000000000008'
\set terminalUserID 'ab150000-0000-0000-0000-000000000009'
\set ticketTypeID 'ab150000-0000-0000-0000-00000000000a'
\set validUserID 'ab150000-0000-0000-0000-00000000000b'
\set waitlistUserID 'ab150000-0000-0000-0000-00000000000c'

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
    'offer-trigger-community',
    'Offer Trigger Community',
    'Community for admission offer trigger tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Categories
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Offer Trigger Group',
    'offer-trigger-group'
);

-- Enrollment users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'attendeeUserID', 'hash-attendee', 'attendee@example.test', true, 'attendee-user'),
    (:'purchaseUserID', 'hash-purchase', 'purchase@example.test', true, 'purchase-user'),
    (:'requestUserID', 'hash-request', 'request@example.test', true, 'request-user'),
    (:'terminalUserID', 'hash-terminal', 'terminal@example.test', true, 'terminal-user'),
    (:'validUserID', 'hash-valid', 'valid@example.test', true, 'valid-user'),
    (:'waitlistUserID', 'hash-waitlist', 'waitlist@example.test', true, 'waitlist-user');

-- Ticketed event
insert into event (
    event_id,
    capacity,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    :'eventID',
    20,
    'Event for admission offer trigger tests',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Offer Trigger Event',
    'offer-trigger-event',
    'UTC'
);

insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeID',
    :'eventID',
    1,
    20,
    'General admission'
);

-- Confirmed attendee conflicting with new offers
insert into event_attendee (event_id, user_id, status)
values (:'eventID', :'attendeeUserID', 'confirmed');

-- Canceled attendance that no longer blocks new offers
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values (
    current_timestamp,
    :'terminalUserID',
    :'eventID',
    'attendance-canceled',
    :'terminalUserID'
);

-- Pending invitation request conflicting with new offers
insert into event_invitation_request (event_id, event_ticket_type_id, user_id, status)
values (:'eventID', :'ticketTypeID', :'requestUserID', 'pending');

-- Waitlist entry conflicting with new offers
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'eventID', :'ticketTypeID', :'waitlistUserID');

-- Completed purchase conflicting with new offers
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    null,
    :'eventID',
    :'ticketTypeID',
    'completed',
    'General admission',
    :'purchaseUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an offer without conflicting enrollment
select lives_ok(
    format(
        $$
            insert into admission_offer (
                event_id,
                event_ticket_type_id,
                expires_at,
                source,
                status,
                user_id
            ) values (
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'organizer_invitation',
                'pending',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'validUserID'
    ),
    'Should accept an offer without conflicting enrollment'
);

-- Should reject active enrollment conflicts
select throws_ok(
    format(
        $$
            insert into admission_offer (
                event_id, event_ticket_type_id, expires_at, source, status, user_id
            ) values (
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'organizer_invitation',
                'pending',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'attendeeUserID'
    ),
    'user already has active attendance for this event',
    'Should reject offers for confirmed attendees'
);

select throws_ok(
    format(
        $$
            insert into admission_offer (
                event_id, event_ticket_type_id, expires_at, source, status, user_id
            ) values (
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'organizer_invitation',
                'pending',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'waitlistUserID'
    ),
    'user is already on the waiting list for this event',
    'Should reject offers for waitlisted users'
);

select throws_ok(
    format(
        $$
            insert into admission_offer (
                event_id, event_ticket_type_id, expires_at, source, status, user_id
            ) values (
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'approval',
                'pending',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'requestUserID'
    ),
    'user already has a pending invitation request for this event',
    'Should reject offers until the pending request is reviewed'
);

select throws_ok(
    format(
        $$
            insert into admission_offer (
                event_id, event_ticket_type_id, expires_at, source, status, user_id
            ) values (
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'organizer_invitation',
                'pending',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'purchaseUserID'
    ),
    'user already has an active purchase for this event',
    'Should reject offers for active purchase owners'
);

-- Should allow offers after terminal attendance
select lives_ok(
    format(
        $$
            insert into admission_offer (
                event_id,
                event_ticket_type_id,
                expires_at,
                source,
                status,
                user_id
            ) values (
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'organizer_invitation',
                'pending',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'terminalUserID'
    ),
    'Should allow offers after terminal attendance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
