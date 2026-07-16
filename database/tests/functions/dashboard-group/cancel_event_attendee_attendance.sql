-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '3a070000-0000-0000-0000-000000000001'
\set attendeeID '3a070000-0000-0000-0000-000000000002'
\set communityID '3a070000-0000-0000-0000-000000000003'
\set eventCanceledID '3a070000-0000-0000-0000-000000000004'
\set eventCategoryID '3a070000-0000-0000-0000-000000000005'
\set eventID '3a070000-0000-0000-0000-000000000006'
\set eventLimitedID '3a070000-0000-0000-0000-000000000007'
\set eventPaidID '3a070000-0000-0000-0000-000000000008'
\set eventTicketTypeID '3a070000-0000-0000-0000-000000000009'
\set eventUnpublishedID '3a070000-0000-0000-0000-000000000010'
\set groupCategoryID '3a070000-0000-0000-0000-000000000011'
\set groupID '3a070000-0000-0000-0000-000000000012'
\set limitedAttendeeID '3a070000-0000-0000-0000-000000000013'
\set paidAttendeeID '3a070000-0000-0000-0000-000000000014'
\set promotedUserID '3a070000-0000-0000-0000-000000000015'
\set purchaseID '3a070000-0000-0000-0000-000000000016'
\set unknownGroupID '3a070000-0000-0000-0000-000000000017'

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
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Users
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values
    ('hash-actor', 'actor@example.com', true, 'Actor', :'actorID', 'actor'),
    ('hash-attendee', 'attendee@example.com', true, 'Attendee', :'attendeeID', 'attendee'),
    ('hash-limited', 'limited@example.com', true, 'Limited', :'limitedAttendeeID', 'limited'),
    ('hash-paid', 'paid@example.com', true, 'Paid', :'paidAttendeeID', 'paid'),
    ('hash-promoted', 'promoted@example.com', true, 'Promoted', :'promotedUserID', 'promoted');

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
    capacity,
    waitlist_enabled,
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
        null,
        true,
        false,
        null,
        false,
        now() + interval '7 days'
    ), (
        :'eventCanceledID',
        'Canceled Event',
        'canceled-event',
        'Test canceled event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        true,
        null,
        false,
        now() + interval '7 days'
    ), (
        :'eventLimitedID',
        'Limited Event',
        'limited-event',
        'Test limited event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        false,
        1,
        true,
        now() + interval '7 days'
    ), (
        :'eventPaidID',
        'Paid Event',
        'paid-event',
        'Test paid event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'USD',
        true,
        false,
        null,
        false,
        now() + interval '7 days'
    ), (
        :'eventUnpublishedID',
        'Unpublished Event',
        'unpublished-event',
        'Test unpublished event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        false,
        false,
        null,
        false,
        now() + interval '7 days'
    );

-- Ticket type and paid purchase
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'eventTicketTypeID', :'eventPaidID', 1, 10, 'Paid admission');

-- Completed paid purchase linked to the paid attendee
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
)
values (
    2500,
    'USD',
    :'eventPaidID',
    :'purchaseID',
    :'eventTicketTypeID',
    'completed',
    'Paid admission',
    :'paidAttendeeID'
);

-- Attendees including a checked-in row whose active state must be cleared
insert into event_attendee (checked_in, checked_in_at, event_id, status, user_id)
values
    (true, current_timestamp, :'eventID', 'confirmed', :'attendeeID'),
    (false, null, :'eventLimitedID', 'confirmed', :'limitedAttendeeID'),
    (false, null, :'eventPaidID', 'confirmed', :'paidAttendeeID');

-- Waitlist entries
insert into event_waitlist (event_id, user_id, created_at)
values (:'eventLimitedID', :'promotedUserID', now());

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel confirmed attendance.
select results_eq(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L)::jsonb $$,
        :'actorID', :'groupID', :'eventID', :'attendeeID'
    ),
    $$ values ('{"left_status": "attendee", "promoted_user_ids": []}'::jsonb) $$,
    'Should cancel a confirmed attendance'
);

select results_eq(
    format($$
        select
            attendance_canceled_at is not null,
            attendance_canceled_by_user_id,
            checked_in,
            checked_in_at,
            status
        from event_attendee
        where event_id = %L::uuid
        and user_id = %L::uuid
    $$, :'eventID', :'attendeeID'),
    format($$ values (true, %L::uuid, false, null::timestamptz, 'attendance-canceled'::text) $$, :'actorID'),
    'Should preserve inactive attendee history'
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
    format(
        $$
        values (
            'event_attendee_attendance_canceled',
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'user',
            '{"event_id": "%s", "user_id": "%s"}'::jsonb
        )
        $$,
        :'actorID', :'communityID', :'eventID', :'groupID', :'attendeeID', :'eventID', :'attendeeID'
    ),
    'Should create the expected audit row'
);

-- Should reject canceling missing confirmed attendees.
select throws_ok(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventID', :'attendeeID'
    ),
    'confirmed event attendee not found',
    'Should reject canceling missing confirmed attendance'
);

-- Should reject events outside the selected group.
select throws_ok(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L) $$,
        :'actorID', :'unknownGroupID', :'eventID', :'attendeeID'
    ),
    'event not found or inactive',
    'Should reject events outside the selected group'
);

-- Should reject paid attendees.
select throws_ok(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventPaidID', :'paidAttendeeID'
    ),
    'paid attendees cannot be canceled from attendee actions',
    'Should reject paid attendee cancellation'
);

select is(
    (select count(*)::int from event_attendee where event_id = :'eventPaidID' and user_id = :'paidAttendeeID'),
    1,
    'Should keep paid attendee rows'
);

select is(
    (select status from event_purchase where event_purchase_id = :'purchaseID'),
    'completed',
    'Should keep paid purchases unchanged'
);

-- Should promote a waitlisted user when canceling from a full event.
select results_eq(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L)::jsonb $$,
        :'actorID', :'groupID', :'eventLimitedID', :'limitedAttendeeID'
    ),
    format(
        $$ values ('{"left_status": "attendee", "promoted_user_ids": ["%s"]}'::jsonb) $$,
        :'promotedUserID'
    ),
    'Should return promoted waitlisted user ids'
);

select results_eq(
    format(
        $$
        select
            ea.status,
            not exists (
                select 1
                from event_waitlist ew
                where ew.event_id = %L::uuid
                and ew.user_id = %L::uuid
            )
        from event_attendee ea
        where ea.event_id = %L::uuid
        and ea.user_id = %L::uuid
        $$,
        :'eventLimitedID', :'promotedUserID', :'eventLimitedID', :'promotedUserID'
    ),
    $$ values ('confirmed'::text, true) $$,
    'Should promote the waitlisted user into attendees'
);

-- Should reject unpublished events.
select throws_ok(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventUnpublishedID', :'attendeeID'
    ),
    'event not found or inactive',
    'Should reject unpublished events'
);

-- Should reject canceled events.
select throws_ok(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventCanceledID', :'attendeeID'
    ),
    'event not found or inactive',
    'Should reject canceled events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
