-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCheckoutUserID '92000000-0000-0000-0000-000000000041'
\set categoryID '92000000-0000-0000-0000-000000000011'
\set allianceID '92000000-0000-0000-0000-000000000001'
\set confirmedUserID '92000000-0000-0000-0000-000000000042'
\set eventCategoryID '92000000-0000-0000-0000-000000000012'
\set expiredCheckoutUserID '92000000-0000-0000-0000-000000000043'
\set groupID '92000000-0000-0000-0000-000000000021'
\set manualPendingUserID '92000000-0000-0000-0000-000000000044'
\set ticketedEventID '92000000-0000-0000-0000-000000000031'
\set ticketTypeID '92000000-0000-0000-0000-000000000051'
\set unticketedEventID '92000000-0000-0000-0000-000000000032'
\set unticketedPendingUserID '92000000-0000-0000-0000-000000000045'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (
    :'allianceID',
    'seat-count-alliance',
    'Seat Count Alliance',
    'Alliance for occupied seat count tests',
    'https://example.com/logo.png',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'categoryID', :'allianceID', 'Technology');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Meetup');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'categoryID', 'Seat Count Group', 'seat-count-group');

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified) values
    (:'activeCheckoutUserID', gen_random_bytes(32), 'active-checkout@example.com', 'active-checkout', true),
    (:'confirmedUserID', gen_random_bytes(32), 'confirmed@example.com', 'confirmed', true),
    (:'expiredCheckoutUserID', gen_random_bytes(32), 'expired-checkout@example.com', 'expired-checkout', true),
    (:'manualPendingUserID', gen_random_bytes(32), 'manual-pending@example.com', 'manual-pending', true),
    (:'unticketedPendingUserID', gen_random_bytes(32), 'unticketed-pending@example.com', 'unticketed-pending', true);

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    capacity,
    payment_currency_code,
    starts_at,
    registration_questions
) values (
    :'ticketedEventID',
    :'groupID',
    'Ticketed Questions Event',
    'ticketed-questions-event',
    'Ticketed event for occupied seat count tests',
    'UTC',
    :'eventCategoryID',
    'in-person',
    5,
    'USD',
    '2030-01-01 10:00:00+00',
    '[{"id": "92000000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb
), (
    :'unticketedEventID',
    :'groupID',
    'Unticketed Questions Event',
    'unticketed-questions-event',
    'Unticketed event for occupied seat count tests',
    'UTC',
    :'eventCategoryID',
    'in-person',
    5,
    null,
    '2030-01-02 10:00:00+00',
    '[{"id": "92000000-0000-0000-0000-000000000102", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb
);

-- Ticket type
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'ticketTypeID', :'ticketedEventID', 1, 5, 'General admission');

-- Attendees
insert into event_attendee (event_id, user_id, manually_invited, status) values
    (:'ticketedEventID', :'activeCheckoutUserID', false, 'registration-questions-pending'),
    (:'ticketedEventID', :'confirmedUserID', false, 'confirmed'),
    (:'ticketedEventID', :'expiredCheckoutUserID', false, 'registration-questions-pending'),
    (:'ticketedEventID', :'manualPendingUserID', true, 'registration-questions-pending'),
    (:'unticketedEventID', :'unticketedPendingUserID', false, 'registration-questions-pending');

-- Event purchases
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    1000,
    'USD',
    :'ticketedEventID',
    :'ticketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'activeCheckoutUserID'
), (
    1000,
    'USD',
    :'ticketedEventID',
    :'ticketTypeID',
    current_timestamp - interval '10 minutes',
    'pending',
    'General admission',
    :'expiredCheckoutUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude expired checkout-created pending registration rows for ticketed events
select is(
    get_event_occupied_seat_count(:'ticketedEventID'::uuid),
    3,
    'Should count confirmed, manual pending, and active checkout pending seats only'
);

-- Should count pending registration rows for unticketed events
select is(
    get_event_occupied_seat_count(:'unticketedEventID'::uuid),
    1,
    'Should count unticketed pending registration rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
