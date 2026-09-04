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

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'activeCheckoutUserID');
select fx_user(:'expiredCheckoutUserID');
select fx_user(:'expiredOfferUserID');
select fx_user(:'manualPendingUserID');
select fx_user(:'refundPurchaseUserID');
select fx_user(:'ticketOfferUserID');
select fx_user(:'freePendingUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

select fx_user(:'confirmedUserID', jsonb_build_object('username', 'confirmed'));

-- Events
select fx_event(:'ticketedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 5,
    'payment_currency_code', 'USD',
    'registration_questions', jsonb_build_array(jsonb_build_object(
        'id', :'question1ID',
        'kind', 'free-text',
        'options', jsonb_build_array(),
        'prompt', 'Note',
        'required', true
    )),
    'starts_at', '2030-01-01 10:00:00+00'
));
select fx_event(:'freeEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 5,
    'registration_questions', jsonb_build_array(jsonb_build_object(
        'id', :'question2ID',
        'kind', 'free-text',
        'options', jsonb_build_array(),
        'prompt', 'Note',
        'required', true
    )),
    'starts_at', '2030-01-02 10:00:00+00'
));
select fx_event(:'offerEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 5,
    'payment_currency_code', 'USD',
    'starts_at', '2030-01-03 10:00:00+00'
));
select fx_event(:'refundEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 5,
    'payment_currency_code', 'USD',
    'starts_at', '2030-01-04 10:00:00+00'
));

-- Ticket types
select fx_event_ticket_type(:'ticketTypeID', :'ticketedEventID', jsonb_build_object(
    'seats_total', 5,
    'title', 'General admission'
));
select fx_event_ticket_type(:'freeTicketTypeID', :'freeEventID', jsonb_build_object(
    'seats_total', 5,
    'title', 'General admission'
));
select fx_event_ticket_type(:'offerTicketTypeID', :'offerEventID', jsonb_build_object(
    'seats_total', 5,
    'title', 'General admission'
));
select fx_event_ticket_type(:'refundTicketTypeID', :'refundEventID', jsonb_build_object(
    'seats_total', 5,
    'title', 'General admission'
));

-- Price windows supporting the event ticket fixtures
select fx_event_ticket_price_window(:'ticketPriceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 1000));
select fx_event_ticket_price_window(:'freePriceWindowID', :'freeTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'offerPriceWindowID', :'offerTicketTypeID', jsonb_build_object('amount_minor', 1000));
select fx_event_ticket_price_window(:'refundPriceWindowID', :'refundTicketTypeID', jsonb_build_object('amount_minor', 1000));

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
