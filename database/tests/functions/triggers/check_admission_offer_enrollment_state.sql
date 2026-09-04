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

-- Baseline community, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'attendeeUserID');
select fx_user(:'purchaseUserID');
select fx_user(:'requestUserID');
select fx_user(:'terminalUserID');
select fx_user(:'validUserID');
select fx_user(:'waitlistUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Ticketed event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('capacity', 20));

select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 20,
    'title', 'General admission'
));

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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
