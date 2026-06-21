-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '00000000-0000-0000-0000-000000000001'
\set attendeeID '00000000-0000-0000-0000-000000000002'
\set categoryID '00000000-0000-0000-0000-000000000003'
\set allianceID '00000000-0000-0000-0000-000000000004'
\set eventCategoryID '00000000-0000-0000-0000-000000000005'
\set eventID '00000000-0000-0000-0000-000000000006'
\set eventPaidID '00000000-0000-0000-0000-000000000007'
\set eventTicketTypeID '00000000-0000-0000-0000-000000000008'
\set groupID '00000000-0000-0000-0000-000000000009'
\set paidAttendeeID '00000000-0000-0000-0000-000000000010'
\set purchaseID '00000000-0000-0000-0000-000000000011'

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
    ('hash-attendee', 'attendee@example.com', true, 'Attendee', :'attendeeID', 'attendee'),
    ('hash-paid', 'paid@example.com', true, 'Paid', :'paidAttendeeID', 'paid');

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
    (:'eventID', 'Free Event', 'free-event', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', null, true, now() + interval '7 days'),
    (:'eventPaidID', 'Paid Event', 'paid-event', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', 'USD', true, now() + interval '7 days');

-- Ticket type and paid purchase
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'eventTicketTypeID', :'eventPaidID', 1, 10, 'Paid admission');

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
values (2500, 'USD', :'eventPaidID', :'purchaseID', :'eventTicketTypeID', 'completed', 'Paid admission', :'paidAttendeeID');

-- Attendees
insert into event_attendee (event_id, user_id, status)
values
    (:'eventID', :'attendeeID', 'confirmed'),
    (:'eventPaidID', :'paidAttendeeID', 'confirmed');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel confirmed attendance.
select results_eq(
    $$ select cancel_event_attendee_attendance(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000009',
        '00000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000002'
    )::jsonb $$,
    $$ values ('{"left_status": "attendee", "promoted_user_ids": []}'::jsonb) $$,
    'Should cancel a confirmed attendance'
);

select is(
    (select count(*)::int from event_attendee where event_id = :'eventID' and user_id = :'attendeeID'),
    0,
    'Should remove the attendee row'
);

-- Should create the expected audit row.
select results_eq(
    $$
        select
            action,
            actor_user_id,
            alliance_id,
            event_id,
            group_id,
            resource_id,
            resource_type,
            details
        from audit_log
    $$,
    $$
        values (
            'event_attendee_attendance_canceled',
            '00000000-0000-0000-0000-000000000001'::uuid,
            '00000000-0000-0000-0000-000000000004'::uuid,
            '00000000-0000-0000-0000-000000000006'::uuid,
            '00000000-0000-0000-0000-000000000009'::uuid,
            '00000000-0000-0000-0000-000000000002'::uuid,
            'user',
            '{"event_id": "00000000-0000-0000-0000-000000000006", "user_id": "00000000-0000-0000-0000-000000000002"}'::jsonb
        )
    $$,
    'Should create the expected audit row'
);

-- Should reject canceling missing confirmed attendees.
select throws_ok(
    $$ select cancel_event_attendee_attendance(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000009',
        '00000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000002'
    ) $$,
    'confirmed event attendee not found',
    'Should reject canceling missing confirmed attendance'
);

-- Should reject events outside the selected group.
select throws_ok(
    $$ select cancel_event_attendee_attendance(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-999999999999',
        '00000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000002'
    ) $$,
    'event not found or inactive',
    'Should reject events outside the selected group'
);

-- Should reject paid attendees.
select throws_ok(
    $$ select cancel_event_attendee_attendance(
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000009',
        '00000000-0000-0000-0000-000000000007',
        '00000000-0000-0000-0000-000000000010'
    ) $$,
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
