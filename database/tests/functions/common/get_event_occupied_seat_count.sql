-- Tests counting event-level occupied seats.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCheckoutUserID '0c070000-0000-0000-0000-000000000001'
\set communityID '0c070000-0000-0000-0000-000000000002'
\set confirmedUserID '0c070000-0000-0000-0000-000000000003'
\set eventCategoryID '0c070000-0000-0000-0000-000000000004'
\set expiredCheckoutUserID '0c070000-0000-0000-0000-000000000005'
\set expiredOfferUserID '0c070000-0000-0000-0000-000000000016'
\set freeEventID '0c070000-0000-0000-0000-00000000000d'
\set freePendingUserID '0c070000-0000-0000-0000-00000000000e'
\set freePriceWindowID '0c070000-0000-0000-0000-000000000019'
\set freeTicketTypeID '0c070000-0000-0000-0000-000000000011'
\set groupCategoryID '0c070000-0000-0000-0000-000000000006'
\set groupID '0c070000-0000-0000-0000-000000000007'
\set manualPendingUserID '0c070000-0000-0000-0000-000000000008'
\set offerEventID '0c070000-0000-0000-0000-000000000012'
\set offerPriceWindowID '0c070000-0000-0000-0000-000000000017'
\set offerTicketTypeID '0c070000-0000-0000-0000-000000000013'
\set question1ID '0c070000-0000-0000-0000-000000000009'
\set question2ID '0c070000-0000-0000-0000-00000000000a'
\set refundEventID '0c070000-0000-0000-0000-000000000014'
\set refundPriceWindowID '0c070000-0000-0000-0000-000000000018'
\set refundPurchaseUserID '0c070000-0000-0000-0000-00000000000f'
\set refundTicketTypeID '0c070000-0000-0000-0000-000000000015'
\set ticketedEventID '0c070000-0000-0000-0000-00000000000b'
\set ticketOfferUserID '0c070000-0000-0000-0000-000000000010'
\set ticketPriceWindowID '0c070000-0000-0000-0000-00000000001a'
\set ticketTypeID '0c070000-0000-0000-0000-00000000000c'

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
    'seat-count-community',
    'Seat Count Community',
    'Community for occupied seat count tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Seat Count Group', 'seat-count-group');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username
) values (
    :'activeCheckoutUserID',
    gen_random_bytes(32),
    'active-checkout@example.com',
    true,
    'active-checkout'
), (
    :'confirmedUserID',
    gen_random_bytes(32),
    'confirmed@example.com',
    true,
    'confirmed'
), (
    :'expiredCheckoutUserID',
    gen_random_bytes(32),
    'expired-checkout@example.com',
    true,
    'expired-checkout'
), (
    :'expiredOfferUserID',
    gen_random_bytes(32),
    'expired-offer@example.com',
    true,
    'expired-offer'
), (
    :'manualPendingUserID',
    gen_random_bytes(32),
    'manual-pending@example.com',
    true,
    'manual-pending'
), (
    :'refundPurchaseUserID',
    gen_random_bytes(32),
    'refund-purchase@example.com',
    true,
    'refund-purchase'
), (
    :'ticketOfferUserID',
    gen_random_bytes(32),
    'ticket-offer@example.com',
    true,
    'ticket-offer'
), (
    :'freePendingUserID',
    gen_random_bytes(32),
    'free-pending@example.com',
    true,
    'free-pending'
);

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
    jsonb_build_array(jsonb_build_object(
        'id', :'question1ID',
        'kind', 'free-text',
        'options', jsonb_build_array(),
        'prompt', 'Note',
        'required', true
    ))
), (
    :'freeEventID',
    :'groupID',
    'Free Questions Event',
    'free-questions-event',
    'Free event for occupied seat count tests',
    'UTC',
    :'eventCategoryID',
    'in-person',
    5,
    null,
    '2030-01-02 10:00:00+00',
    jsonb_build_array(jsonb_build_object(
        'id', :'question2ID',
        'kind', 'free-text',
        'options', jsonb_build_array(),
        'prompt', 'Note',
        'required', true
    ))
), (
    :'offerEventID',
    :'groupID',
    'Offer Event',
    'offer-event',
    'Event for active and expired offer counts',
    'UTC',
    :'eventCategoryID',
    'in-person',
    5,
    'USD',
    '2030-01-03 10:00:00+00',
    '[]'::jsonb
), (
    :'refundEventID',
    :'groupID',
    'Refund Event',
    'refund-event',
    'Event for refund reservation counts',
    'UTC',
    :'eventCategoryID',
    'in-person',
    5,
    'USD',
    '2030-01-04 10:00:00+00',
    '[]'::jsonb
);

-- Ticket types
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values
    (:'ticketTypeID', :'ticketedEventID', 1, 5, 'General admission'),
    (:'freeTicketTypeID', :'freeEventID', 1, 5, 'General admission'),
    (:'offerTicketTypeID', :'offerEventID', 1, 5, 'General admission'),
    (:'refundTicketTypeID', :'refundEventID', 1, 5, 'General admission');

-- Price windows supporting the event ticket fixtures
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
)
values
    (:'ticketPriceWindowID', 1000, :'ticketTypeID'),
    (:'freePriceWindowID', 0, :'freeTicketTypeID'),
    (:'offerPriceWindowID', 1000, :'offerTicketTypeID'),
    (:'refundPriceWindowID', 1000, :'refundTicketTypeID');

-- Attendees
insert into event_attendee (
    event_id,
    user_id,
    manually_invited,
    status
) values (
    :'ticketedEventID',
    :'activeCheckoutUserID',
    false,
    'registration-questions-pending'
), (
    :'ticketedEventID',
    :'confirmedUserID',
    false,
    'confirmed'
), (
    :'ticketedEventID',
    :'expiredCheckoutUserID',
    false,
    'registration-questions-pending'
), (
    :'freeEventID',
    :'freePendingUserID',
    false,
    'registration-questions-pending'
);

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
    0,
    'USD',
    :'ticketedEventID',
    :'ticketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'activeCheckoutUserID'
), (
    0,
    'USD',
    :'ticketedEventID',
    :'ticketTypeID',
    null,
    'completed',
    'General admission',
    :'confirmedUserID'
), (
    0,
    'USD',
    :'ticketedEventID',
    :'ticketTypeID',
    current_timestamp - interval '10 minutes',
    'pending',
    'General admission',
    :'expiredCheckoutUserID'
);

-- Active free organizer invitation offer
insert into admission_offer (
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    current_timestamp,
    :'freeEventID',
    :'freeTicketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'manualPendingUserID'
);

-- Active organizer offer counted for the dedicated offer event
insert into admission_offer (
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    current_timestamp,
    :'offerEventID',
    :'offerTicketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'ticketOfferUserID'
);

-- Expired organizer offer excluded from the dedicated offer event
insert into admission_offer (
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    current_timestamp - interval '2 hours',
    :'offerEventID',
    :'offerTicketTypeID',
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'pending',
    :'expiredOfferUserID'
);

-- Refund-processing purchase reserving the dedicated refund event
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
    'USD',
    :'refundEventID',
    :'refundTicketTypeID',
    'refund-pending',
    'General admission',
    :'refundPurchaseUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude expired checkout-created pending registration rows for ticketed events
select is(
    get_event_occupied_seat_count(:'ticketedEventID'::uuid),
    2,
    'Should count confirmed and active checkout pending seats only'
);

-- Should count active offers without counting expired offers
select is(
    get_event_occupied_seat_count(:'offerEventID'::uuid),
    1,
    'Should count active offers without counting expired offers'
);

-- Should count refund-processing purchases without attendee rows
select is(
    get_event_occupied_seat_count(:'refundEventID'::uuid),
    1,
    'Should count refund-processing purchases without attendee rows'
);

-- Should exclude unowned pending registration rows while counting active offers
select is(
    get_event_occupied_seat_count(:'freeEventID'::uuid),
    1,
    'Should count active offers but exclude unowned pending registration rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
