-- Tests preparing event checkout purchases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(59);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendeeUserID '79100000-0000-0000-0000-000000000022'
\set cacheUserID '79100000-0000-0000-0000-000000000073'
\set checkoutUserID '79100000-0000-0000-0000-000000000023'
\set closedWindowEventID '79100000-0000-0000-0000-000000000041'
\set closedWindowMatchingPurchaseID '79100000-0000-0000-0000-000000000042'
\set closedWindowMatchingUserID '79100000-0000-0000-0000-000000000043'
\set closedWindowMismatchedPurchaseID '79100000-0000-0000-0000-000000000044'
\set closedWindowMismatchedUserID '79100000-0000-0000-0000-000000000045'
\set closedWindowNewUserID '79100000-0000-0000-0000-000000000046'
\set closedWindowPriceWindowAID '79100000-0000-0000-0000-000000000049'
\set closedWindowPriceWindowBID '79100000-0000-0000-0000-00000000004a'
\set closedWindowTicketTypeAID '79100000-0000-0000-0000-000000000047'
\set closedWindowTicketTypeBID '79100000-0000-0000-0000-000000000048'
\set communityID '79100000-0000-0000-0000-000000000001'
\set completedPurchaseID '79100000-0000-0000-0000-000000000019'
\set completedUserID '79100000-0000-0000-0000-000000000024'
\set discountUserID '79100000-0000-0000-0000-000000000028'
\set endedWindowDiscountOfferID '79100000-0000-0000-0000-000000000077'
\set endedWindowDiscountUserID '79100000-0000-0000-0000-000000000078'
\set endedWindowOfferID '79100000-0000-0000-0000-000000000079'
\set endedWindowUserID '79100000-0000-0000-0000-00000000007a'
\set endedWindowWaitlistOfferID '79100000-0000-0000-0000-00000000007d'
\set endedWindowWaitlistUserID '79100000-0000-0000-0000-00000000007e'
\set eventCategoryID '79100000-0000-0000-0000-000000000002'
\set exhaustedDiscountUserID '79100000-0000-0000-0000-000000000027'
\set freeDiscountID '79100000-0000-0000-0000-000000000016'
\set freeEventID '79100000-0000-0000-0000-00000000004e'
\set freeGroupID '79100000-0000-0000-0000-00000000004d'
\set freePriceWindowID '79100000-0000-0000-0000-000000000050'
\set freeTicketTypeID '79100000-0000-0000-0000-00000000004f'
\set freeUserID '79100000-0000-0000-0000-000000000051'
\set groupCategoryID '79100000-0000-0000-0000-000000000010'
\set groupID '79100000-0000-0000-0000-000000000011'
\set inactiveDiscountID '79100000-0000-0000-0000-000000000017'
\set inactiveEventID '79100000-0000-0000-0000-000000000005'
\set inactivePriceWindowID '79100000-0000-0000-0000-000000000015'
\set inactiveTicketTypeID '79100000-0000-0000-0000-000000000009'
\set inactiveUserID '79100000-0000-0000-0000-000000000030'
\set ineffectiveDiscountID '79100000-0000-0000-0000-00000000006c'
\set ineffectiveDiscountOfferID '79100000-0000-0000-0000-00000000006d'
\set ineffectiveDiscountPriceWindowID '79100000-0000-0000-0000-00000000006e'
\set ineffectiveDiscountTicketTypeID '79100000-0000-0000-0000-00000000006f'
\set ineffectiveDiscountUserID '79100000-0000-0000-0000-000000000070'
\set invalidDiscountUserID '79100000-0000-0000-0000-000000000025'
\set invitedPendingPurchaseID '79100000-0000-0000-0000-000000000040'
\set invitedUserID '79100000-0000-0000-0000-000000000039'
\set limitedDiscountID '79100000-0000-0000-0000-000000000018'
\set liveSnapshotOfferID '79100000-0000-0000-0000-00000000007b'
\set liveSnapshotUserID '79100000-0000-0000-0000-00000000007c'
\set mainEventID '79100000-0000-0000-0000-000000000003'
\set manualTaxEventID '79100000-0000-0000-0000-0000000000a3'
\set manualTaxPriceWindowID '79100000-0000-0000-0000-0000000000a4'
\set manualTaxTicketTypeID '79100000-0000-0000-0000-0000000000a5'
\set manualTaxUserID '79100000-0000-0000-0000-000000000074'
\set offerDiscountID '79100000-0000-0000-0000-00000000005a'
\set offerDiscountUserID '79100000-0000-0000-0000-00000000005b'
\set offerFreeID '79100000-0000-0000-0000-00000000005c'
\set offerFreeUserID '79100000-0000-0000-0000-00000000005d'
\set offerPaidID '79100000-0000-0000-0000-00000000005e'
\set offerPaidUserID '79100000-0000-0000-0000-00000000005f'
\set offerPrivatePriceWindowID '79100000-0000-0000-0000-000000000060'
\set offerPrivateTicketTypeID '79100000-0000-0000-0000-000000000061'
\set offerWrongUserID '79100000-0000-0000-0000-000000000062'
\set paymentSetupUnavailableEventID '79100000-0000-0000-0000-000000000064'
\set paymentSetupUnavailablePriceWindowID '79100000-0000-0000-0000-000000000065'
\set paymentSetupUnavailableTicketTypeID '79100000-0000-0000-0000-000000000066'
\set paymentSetupUnavailableUserID '79100000-0000-0000-0000-000000000067'
\set platformFeeMaxUserID '79100000-0000-0000-0000-000000000072'
\set platformFeeUserID '79100000-0000-0000-0000-000000000071'
\set priceUnavailableEventID '79100000-0000-0000-0000-000000000068'
\set priceUnavailablePriceWindowID '79100000-0000-0000-0000-000000000069'
\set priceUnavailableTicketTypeID '79100000-0000-0000-0000-00000000006a'
\set priceUnavailableUserID '79100000-0000-0000-0000-00000000006b'
\set priceWindowAID '79100000-0000-0000-0000-000000000012'
\set priceWindowBID '79100000-0000-0000-0000-000000000013'
\set questionsEventID '79100000-0000-0000-0000-000000000035'
\set questionsPriceWindowID '79100000-0000-0000-0000-000000000036'
\set questionsTicketTypeID '79100000-0000-0000-0000-000000000037'
\set questionsUserID '79100000-0000-0000-0000-000000000038'
\set queueCheckoutUserID '79100000-0000-0000-0000-000000000052'
\set queueDiscountID '79100000-0000-0000-0000-000000000063'
\set queueEventID '79100000-0000-0000-0000-000000000053'
\set queueExpiredPurchaseID '79100000-0000-0000-0000-000000000054'
\set queueHolderUserID '79100000-0000-0000-0000-000000000055'
\set queuePriceWindowID '79100000-0000-0000-0000-000000000056'
\set queueTicketTypeID '79100000-0000-0000-0000-000000000057'
\set queueUserID '79100000-0000-0000-0000-000000000058'
\set redeemedPurchaseID '79100000-0000-0000-0000-000000000020'
\set redeemedUserID '79100000-0000-0000-0000-000000000031'
\set registrationQuestionID '79100000-0000-0000-0000-000000000101'
\set replacePendingPurchaseID '79100000-0000-0000-0000-0000000000a6'
\set replaceUserID '79100000-0000-0000-0000-0000000000a7'
\set reusePendingPurchaseID '79100000-0000-0000-0000-0000000000a8'
\set reuseUserID '79100000-0000-0000-0000-0000000000a9'
\set soldOutEventID '79100000-0000-0000-0000-000000000004'
\set soldOutHolderUserID '79100000-0000-0000-0000-000000000032'
\set soldOutPendingPurchaseID '79100000-0000-0000-0000-00000000004b'
\set soldOutPendingUserID '79100000-0000-0000-0000-00000000004c'
\set soldOutPriceWindowID '79100000-0000-0000-0000-000000000014'
\set soldOutPurchaseID '79100000-0000-0000-0000-000000000021'
\set soldOutTicketTypeID '79100000-0000-0000-0000-000000000008'
\set soldOutUserID '79100000-0000-0000-0000-000000000029'
\set staleTicketUserID '79100000-0000-0000-0000-0000000000a1'
\set ticketTypeAID '79100000-0000-0000-0000-000000000006'
\set ticketTypeBID '79100000-0000-0000-0000-000000000007'
\set unavailableDiscountUserID '79100000-0000-0000-0000-000000000026'
\set underMinimumDiscountID '79100000-0000-0000-0000-000000000034'
\set underMinimumUserID '79100000-0000-0000-0000-000000000033'
\set unpublishedEventID '79100000-0000-0000-0000-0000000000a2'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID', jsonb_build_object('name', 'prepare-community'));

-- Baseline categories, users and group
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'attendeeUserID');
select fx_user(:'cacheUserID');
select fx_user(:'checkoutUserID');
select fx_user(:'closedWindowMatchingUserID');
select fx_user(:'closedWindowMismatchedUserID');
select fx_user(:'closedWindowNewUserID');
select fx_user(:'completedUserID');
select fx_user(:'discountUserID');
select fx_user(:'endedWindowDiscountUserID');
select fx_user(:'endedWindowUserID');
select fx_user(:'endedWindowWaitlistUserID');
select fx_user(:'exhaustedDiscountUserID');
select fx_user(:'freeUserID');
select fx_user(:'inactiveUserID');
select fx_user(:'ineffectiveDiscountUserID');
select fx_user(:'invalidDiscountUserID');
select fx_user(:'invitedUserID');
select fx_user(:'liveSnapshotUserID');
select fx_user(:'manualTaxUserID');
select fx_user(:'offerDiscountUserID');
select fx_user(:'offerFreeUserID');
select fx_user(:'offerPaidUserID');
select fx_user(:'offerWrongUserID');
select fx_user(:'paymentSetupUnavailableUserID');
select fx_user(:'platformFeeMaxUserID');
select fx_user(:'platformFeeUserID');
select fx_user(:'priceUnavailableUserID');
select fx_user(:'questionsUserID');
select fx_user(:'queueCheckoutUserID');
select fx_user(:'queueHolderUserID');
select fx_user(:'queueUserID');
select fx_user(:'redeemedUserID');
select fx_user(:'replaceUserID');
select fx_user(:'reuseUserID');
select fx_user(:'soldOutHolderUserID');
select fx_user(:'soldOutPendingUserID');
select fx_user(:'soldOutUserID');
select fx_user(:'staleTicketUserID');
select fx_user(:'unavailableDiscountUserID');
select fx_user(:'underMinimumUserID');
select fx_group(:'freeGroupID', :'communityID', :'groupCategoryID');

-- Group configured for Stripe checkout scenarios
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'payment_recipient', jsonb_build_object(
            'provider', 'stripe',
            'recipient_id', 'acct_prepare',
            'seller_display_name', 'Prepare Fiscal Sponsor'
        ),
    'slug', 'prepare-group',
    'slug_pretty', 'prepare-group-pretty'
));

-- Events
select fx_event(:'freeEventID', :'freeGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Venue',
    'venue_state_code', 'OR',
    'venue_zip_code', '97201'
));
select fx_event(:'mainEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'hybrid',
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'slug', 'main-event',
    'starts_at', now() + interval '2 days',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Venue',
    'venue_zip_code', '97201'
));
select fx_event(:'soldOutEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Venue',
    'venue_state_code', 'OR',
    'venue_zip_code', '97201'
));
select fx_event(:'inactiveEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Venue',
    'venue_state_code', 'OR',
    'venue_zip_code', '97201'
));
select fx_event(:'queueEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Venue',
    'venue_state_code', 'OR',
    'venue_zip_code', '97201'
));
-- Event that requires registration answers before checkout can proceed
select fx_event(:'questionsEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'registration_questions', jsonb_build_array(jsonb_build_object(
        'id', :'registrationQuestionID',
        'kind', 'free-text',
        'options', jsonb_build_array(),
        'prompt', 'Note',
        'required', true
    )),
    'starts_at', now() + interval '2 days',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Venue',
    'venue_state_code', 'OR',
    'venue_zip_code', '97201'
));

-- Closed registration window event that is still active
select fx_event(:'closedWindowEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '90 minutes',
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'registration_starts_at', now() - interval '2 hours',
    'starts_at', now() - interval '30 minutes',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Venue',
    'venue_zip_code', '97201'
));

-- Paid event without payment setup used by the readiness conflict
select fx_event(:'paymentSetupUnavailableEventID', :'freeGroupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Venue',
    'venue_zip_code', '97201'
));

-- Event with a lapsed ticket price used by the price availability conflict
select fx_event(:'priceUnavailableEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Venue',
    'venue_zip_code', '97201'
));

-- Unpublished paid event used by the event validation rejection
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', false,
    'starts_at', now() + interval '2 days'
));

-- Manual-tax event whose Tax Rate identifiers are snapshotted on checkout
select fx_event(:'manualTaxEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'manual_tax_rate_ids', array['txr_state', 'txr_local']::text[],
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days',
    'tax_calculation_mode', 'manual',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Venue',
    'venue_zip_code', '97201'
));

-- Ticket types
select fx_event_ticket_type(:'freeTicketTypeID', :'freeEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'ticketTypeAID', :'mainEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'ticketTypeBID', :'mainEventID', jsonb_build_object(
    'order', 2,
    'seats_total', 10
));
select fx_event_ticket_type(:'ineffectiveDiscountTicketTypeID', :'mainEventID', jsonb_build_object(
    'order', 4,
    'seats_total', 10
));
select fx_event_ticket_type(:'closedWindowTicketTypeAID', :'closedWindowEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'closedWindowTicketTypeBID', :'closedWindowEventID', jsonb_build_object(
    'order', 2,
    'seats_total', 10
));
select fx_event_ticket_type(:'queueTicketTypeID', :'queueEventID', jsonb_build_object(
    'seats_total', 1,
    'title', 'Queue admission'
));
select fx_event_ticket_type(:'soldOutTicketTypeID', :'soldOutEventID', jsonb_build_object(
    'seats_total', 1,
    'title', 'General admission'
));
select fx_event_ticket_type(:'inactiveTicketTypeID', :'inactiveEventID', jsonb_build_object(
    'active', false,
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'offerPrivateTicketTypeID', :'mainEventID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 3,
    'seats_total', 10
));
select fx_event_ticket_type(:'questionsTicketTypeID', :'questionsEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Ticket type sold by the manual-tax event
select fx_event_ticket_type(:'manualTaxTicketTypeID', :'manualTaxEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Ticket types dedicated to mutable configuration conflict scenarios
select fx_event_ticket_type(:'paymentSetupUnavailableTicketTypeID', :'paymentSetupUnavailableEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'priceUnavailableTicketTypeID', :'priceUnavailableEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'Price unavailable admission'
));

-- Price windows
select fx_event_ticket_price_window(:'freePriceWindowID', :'freeTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'ineffectiveDiscountPriceWindowID', :'ineffectiveDiscountTicketTypeID', jsonb_build_object('amount_minor', 1));
select fx_event_ticket_price_window(:'priceWindowAID', :'ticketTypeAID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'priceWindowBID', :'ticketTypeBID', jsonb_build_object('amount_minor', 4000));
select fx_event_ticket_price_window(:'closedWindowPriceWindowAID', :'closedWindowTicketTypeAID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'closedWindowPriceWindowBID', :'closedWindowTicketTypeBID', jsonb_build_object('amount_minor', 4000));
select fx_event_ticket_price_window(:'queuePriceWindowID', :'queueTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'soldOutPriceWindowID', :'soldOutTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'inactivePriceWindowID', :'inactiveTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'offerPrivatePriceWindowID', :'offerPrivateTicketTypeID', jsonb_build_object('amount_minor', 3000));
select fx_event_ticket_price_window(:'questionsPriceWindowID', :'questionsTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Current paid price window for the manual-tax event
select fx_event_ticket_price_window(:'manualTaxPriceWindowID', :'manualTaxTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Current paid price window used by the payment readiness conflict
select fx_event_ticket_price_window(:'paymentSetupUnavailablePriceWindowID', :'paymentSetupUnavailableTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Lapsed price window used by the price availability conflict
select fx_event_ticket_price_window(:'priceUnavailablePriceWindowID', :'priceUnavailableTicketTypeID', jsonb_build_object(
    'amount_minor', 2500,
    'ends_at', current_timestamp - interval '1 minute',
    'starts_at', current_timestamp - interval '2 days'
));

-- Discount codes
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    total_available,
    title
) values (
    :'freeDiscountID',
    true,
    2500,
    4,
    true,
    'FREEPASS',
    :'mainEventID',
    'fixed_amount',
    null,
    'Free pass'
), (
    :'inactiveDiscountID',
    false,
    500,
    1,
    true,
    'INACTIVE',
    :'mainEventID',
    'fixed_amount',
    null,
    'Inactive discount'
), (
    :'limitedDiscountID',
    true,
    500,
    5,
    true,
    'TOTAL1',
    :'mainEventID',
    'fixed_amount',
    1,
    'Limited discount'
), (
    :'queueDiscountID',
    true,
    2500,
    1,
    true,
    'QUEUEFREE',
    :'queueEventID',
    'fixed_amount',
    null,
    'Queue free pass'
), (
    :'underMinimumDiscountID',
    true,
    2475,
    5,
    true,
    'UNDERMIN',
    :'mainEventID',
    'fixed_amount',
    null,
    'Under minimum discount'
);

-- Percentage discount too small to reduce the minor-unit price
insert into event_discount_code (
    event_discount_code_id,
    active,
    code,
    event_id,
    kind,
    title,

    available,
    available_override_active,
    percentage
) values (
    :'ineffectiveDiscountID',
    true,
    'TINY25',
    :'mainEventID',
    'percentage',
    'Tiny percentage',

    5,
    true,
    25
);

-- Existing attendee
insert into event_attendee (event_id, user_id)
values (:'mainEventID', :'attendeeUserID');

-- Attendee with a pending invitation alongside a reusable pending purchase
insert into event_attendee (event_id, user_id, manually_invited, status)
values (:'mainEventID', :'invitedUserID', true, 'invitation-pending');

-- Pending purchase held by the invited user
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    :'invitedPendingPurchaseID',
    2500,
    'direct-charge',
    'acct_prepare',
    'USD',
    0,
    :'mainEventID',
    :'ticketTypeAID',
    now() + interval '15 minutes',
    'stripe',
    'acct_prepare',
    '{"connected_account_id":"acct_prepare","display_name":"Prepare Group","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'invitedUserID',
    '{}'::jsonb
);

-- Pending purchases used by the equivalent reuse and mismatched replacement scenarios
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    :'replacePendingPurchaseID',
    2500,
    'direct-charge',
    'acct_prepare',
    'USD',
    0,
    :'mainEventID',
    :'ticketTypeAID',
    now() + interval '15 minutes',
    'stripe',
    'acct_prepare',
    '{"connected_account_id":"acct_prepare","display_name":"Prepare Group","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'replaceUserID',
    '{}'::jsonb
), (
    :'reusePendingPurchaseID',
    2500,
    'direct-charge',
    'acct_prepare',
    'USD',
    0,
    :'mainEventID',
    :'ticketTypeAID',
    now() + interval '15 minutes',
    'stripe',
    'acct_prepare',
    '{"connected_account_id":"acct_prepare","display_name":"Prepare Group","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'reuseUserID',
    '{}'::jsonb
);

-- Pending purchases that should remain reusable after registration or availability closes
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    :'closedWindowMatchingPurchaseID',
    2500,
    'direct-charge',
    'acct_prepare',
    'USD',
    0,
    :'closedWindowEventID',
    :'closedWindowTicketTypeAID',
    now() + interval '15 minutes',
    'stripe',
    'acct_prepare',
    '{"connected_account_id":"acct_prepare","display_name":"Prepare Group","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'closedWindowMatchingUserID',
    '{}'::jsonb
), (
    :'closedWindowMismatchedPurchaseID',
    2500,
    'direct-charge',
    'acct_prepare',
    'USD',
    0,
    :'closedWindowEventID',
    :'closedWindowTicketTypeAID',
    now() + interval '15 minutes',
    'stripe',
    'acct_prepare',
    '{"connected_account_id":"acct_prepare","display_name":"Prepare Group","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'closedWindowMismatchedUserID',
    '{}'::jsonb
), (
    :'queueExpiredPurchaseID',
    2500,
    'direct-charge',
    'acct_prepare',
    'USD',
    0,
    :'queueEventID',
    :'queueTicketTypeID',
    now() - interval '1 minute',
    'stripe',
    'acct_prepare',
    '{"connected_account_id":"acct_prepare","display_name":"Prepare Group","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'Queue admission',
    :'queueHolderUserID',
    '{}'::jsonb
), (
    :'soldOutPendingPurchaseID',
    2500,
    'direct-charge',
    'acct_prepare',
    'USD',
    0,
    :'soldOutEventID',
    :'soldOutTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'acct_prepare',
    '{"connected_account_id":"acct_prepare","display_name":"Prepare Group","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'soldOutPendingUserID',
    '{}'::jsonb
);

-- Existing completed purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    seller_snapshot,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
)
select
    fixtures.event_purchase_id::uuid,
    fixtures.amount_minor,
    fixtures.currency_code,
    fixtures.discount_amount_minor,
    fixtures.discount_code,
    fixtures.event_discount_code_id::uuid,
    fixtures.event_id::uuid,
    fixtures.event_ticket_type_id::uuid,
    fixtures.status,
    fixtures.ticket_title,
    fixtures.user_id::uuid,

    'direct-charge',
    'acct_prepare',
    0,
    'stripe',
    'ch_' || fixtures.event_purchase_id,
    'cs_' || fixtures.event_purchase_id,
    'acct_prepare',
    'pi_' || fixtures.event_purchase_id,
    fixtures.amount_minor,
    '{"connected_account_id":"acct_prepare","display_name":"Prepare Group","provider":"stripe"}'::jsonb,
    fixtures.amount_minor,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
from (values (
    :'completedPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'mainEventID',
    :'ticketTypeAID',
    'completed',
    'General admission',
    :'completedUserID'
), (
    :'redeemedPurchaseID',
    2000,
    'USD',
    500,
    'TOTAL1',
    :'limitedDiscountID',
    :'mainEventID',
    :'ticketTypeAID',
    'completed',
    'General admission',
    :'redeemedUserID'
), (
    :'soldOutPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'soldOutEventID',
    :'soldOutTicketTypeID',
    'completed',
    'General admission',
    :'soldOutHolderUserID'
)) as fixtures (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
);

-- FIFO queue that must take released capacity before direct checkout
insert into event_waitlist (
    created_at,
    event_id,
    event_ticket_type_id,
    user_id
) values (
    current_timestamp,
    :'queueEventID',
    :'queueTicketTypeID',
    :'queueUserID'
);

-- Owned offers for paid, discounted-to-zero, and intrinsic-free claims
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values
    (
        :'ineffectiveDiscountOfferID',
        :'mainEventID',
        :'ineffectiveDiscountTicketTypeID',
        now() + interval '1 day',
        'approval',
        'pending',
        :'ineffectiveDiscountUserID'
    ),
    (
        :'offerDiscountID',
        :'mainEventID',
        :'ticketTypeAID',
        now() + interval '1 day',
        'approval',
        'pending',
        :'offerDiscountUserID'
    ),
    (
        :'offerFreeID',
        :'freeEventID',
        :'freeTicketTypeID',
        now() + interval '1 day',
        'organizer_invitation',
        'pending',
        :'offerFreeUserID'
    ),
    (
        :'offerPaidID',
        :'mainEventID',
        :'offerPrivateTicketTypeID',
        now() + interval '1 day',
        'organizer_invitation',
        'pending',
        :'offerPaidUserID'
    );

-- Pending offers that already have an issue-time or bounced-back price snapshot
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values
    (
        :'endedWindowDiscountOfferID',
        2500,
        'USD',
        0,
        null,
        null,
        :'priceUnavailableEventID',
        :'priceUnavailableTicketTypeID',
        now() + interval '1 day',
        'approval',
        'pending',
        'Price unavailable admission',
        :'endedWindowDiscountUserID'
    ),
    (
        :'endedWindowOfferID',
        2500,
        'USD',
        0,
        null,
        null,
        :'priceUnavailableEventID',
        :'priceUnavailableTicketTypeID',
        now() + interval '1 day',
        'approval',
        'pending',
        'Price unavailable admission',
        :'endedWindowUserID'
    ),
    (
        :'endedWindowWaitlistOfferID',
        2500,
        'USD',
        0,
        null,
        null,
        :'priceUnavailableEventID',
        :'priceUnavailableTicketTypeID',
        now() + interval '1 day',
        'waitlist',
        'pending',
        'Price unavailable admission',
        :'endedWindowWaitlistUserID'
    ),
    (
        :'liveSnapshotOfferID',
        2500,
        'USD',
        0,
        null,
        null,
        :'mainEventID',
        :'ticketTypeAID',
        now() + interval '1 day',
        'approval',
        'pending',
        'General admission',
        :'liveSnapshotUserID'
    );

-- Account-scoped tax location reused by the cache-reuse scenario
insert into payment_provider_tax_location (
    connected_seller_id,
    fingerprint,
    payment_provider_id,
    provider_tax_location_id,
    venue_snapshot
)
select
    'acct_prepare',
    encode(
        digest(
            convert_to('1 Main St', 'UTF8') || decode('00', 'hex')
            || convert_to('Portland', 'UTF8') || decode('00', 'hex')
            || convert_to('US', 'UTF8') || decode('00', 'hex')
            || convert_to('Venue', 'UTF8') || decode('00', 'hex')
            || convert_to('', 'UTF8') || decode('00', 'hex')
            || convert_to('97201', 'UTF8') || decode('00', 'hex'),
            'sha256'
        ),
        'hex'
    ),
    'stripe',
    'loc_cached',
    '{
        "address": "1 Main St",
        "city": "Portland",
        "country_code": "US",
        "name": "Venue",
        "state_code": null,
        "state_name": null,
        "zip_code": "97201"
    }'::jsonb;

-- Account-scoped tax product reused by the cache-reuse scenario
insert into payment_provider_tax_product (
    connected_seller_id,
    fingerprint,
    payment_provider_id,
    provider_tax_location_id,
    provider_tax_product_id,
    tax_code,
    title
)
values (
    'acct_prepare',
    encode(
        digest(
            convert_to('General admission', 'UTF8') || decode('00', 'hex')
            || convert_to('loc_cached', 'UTF8') || decode('00', 'hex')
            || convert_to('txcd_50013001', 'UTF8') || decode('00', 'hex'),
            'sha256'
        ),
        'hex'
    ),
    'stripe',
    'loc_cached',
    'prod_cached',
    'txcd_50013001',
    'General admission'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should prepare intrinsic zero-price checkout without payment setup
select results_eq(
    format(
        $$
            with prepared_checkout as (
                select prepare_event_checkout_purchase(
                    %L::uuid,
                    %L::uuid,
                    %L::uuid,
                    %L::uuid,
                    null,
                    null,
                    null,
                    null,
                    250
                ) as checkout
            )
            select
                checkout->>'amount_minor',
                checkout ? 'currency_code',
                checkout->>'provisional_platform_fee_amount_minor',
                checkout ? 'seller'
            from prepared_checkout
        $$,
        :'communityID',
        :'freeEventID',
        :'freeTicketTypeID',
        :'freeUserID'
    ),
    $$ values ('0'::text, false, '0'::text, false) $$,
    'Should prepare intrinsic zero-price checkout without payment setup'
);

-- Should create a pending checkout purchase
select lives_ok(
    format(
        $$select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe'
        )$$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'checkoutUserID'
    ),
    'Should create a pending checkout purchase'
);

-- Should snapshot paid hybrid admission and its complete physical venue
select results_eq(
    format(
        $$
            select
                e.event_kind_id,
                ep.amount_minor,
                ep.event_ticket_type_id,
                ep.provider_tax_code,
                ep.provisional_platform_fee_amount_minor,
                ep.status,
                ep.tax_classification,
                ep.venue_snapshot
            from event_purchase ep
            join event e using (event_id)
            where ep.event_id = %L::uuid
            and ep.user_id = %L::uuid
            and ep.status = 'pending'
        $$,
        :'mainEventID',
        :'checkoutUserID'
    ),
    format(
        $$
            values (
                'hybrid'::text,
                2500::bigint,
                %L::uuid,
                'txcd_50013001'::text,
                0::bigint,
                'pending'::text,
                'professional-event-admission'::text,
                '{
                    "address": "1 Main St",
                    "city": "Portland",
                    "country_code": "US",
                    "name": "Venue",
                    "state_code": null,
                    "state_name": null,
                    "zip_code": "97201"
                }'::jsonb
            )
        $$,
        :'ticketTypeAID'
    ),
    'Should snapshot paid hybrid admission and its complete physical venue'
);

-- Should return the checkout route and recipient context alongside the purchase
select results_eq(
    format(
        $$
            with prepared_checkout as (
                select prepare_event_checkout_purchase(
                    %L::uuid,
                    %L::uuid,
                    %L::uuid,
                    %L::uuid,
                    null,
                    'stripe'
                ) as checkout
            )
            select
                checkout->>'community_name',
                checkout->>'event_slug',
                checkout->>'group_slug',
                checkout->>'group_slug_pretty',
                checkout->'seller'->>'connected_account_id'
            from prepared_checkout
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'checkoutUserID'
    ),
    $$ values ('prepare-community'::text, 'main-event'::text, 'prepare-group'::text, 'prepare-group-pretty'::text, 'acct_prepare'::text) $$,
    'Should return the checkout route and recipient context alongside the purchase'
);

-- Should reuse an equivalent pending purchase
select is(
    (
        select prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'mainEventID'::uuid,
            :'ticketTypeAID'::uuid,
            :'reuseUserID'::uuid,
            null,
            'stripe'
        )::jsonb->>'event_purchase_id'
    ),
    :'reusePendingPurchaseID',
    'Should reuse an equivalent pending purchase'
);

-- Should replace a mismatched pending purchase
select lives_ok(
    format(
        $$
            select prepare_event_checkout_purchase(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                null,
                'stripe'
            )
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeBID',
        :'replaceUserID'
    ),
    'Should replace a mismatched pending purchase'
);

-- Should create the requested pending purchase and expire the previous one
select results_eq(
    format(
        $$
            select
                event_purchase_id = %3$L::uuid,
                event_ticket_type_id,
                hold_expires_at,
                status
            from event_purchase
            where event_id = %1$L::uuid
            and user_id = %2$L::uuid
            order by status
        $$,
        :'mainEventID',
        :'replaceUserID',
        :'replacePendingPurchaseID'
    ),
    format(
        $$
            values
                (true, %L::uuid, current_timestamp, 'expired'::text),
                (false, %L::uuid, current_timestamp + interval '15 minutes', 'pending'::text)
        $$,
        :'ticketTypeAID',
        :'ticketTypeBID'
    ),
    'Should create the requested pending purchase and expire the previous one'
);

-- Should return an existing completed purchase with its public charge model
select results_eq(
    format($$
        with prepared as (
            select prepare_event_checkout_purchase(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                null,
                'stripe'
            ) as checkout
        )
        select
            checkout->>'charge_model',
            checkout->>'event_purchase_id',
            checkout->'seller'->>'connected_account_id',
            checkout->>'status'
        from prepared
    $$, :'communityID', :'mainEventID', :'ticketTypeBID', :'completedUserID'),
    format($$ values (
        'direct-charge'::text,
        %L::text,
        'acct_prepare'::text,
        'completed'::text
    ) $$, :'completedPurchaseID'),
    'Should return an existing completed purchase with its public charge model'
);

-- Should snapshot the platform fee from the final amount rounding down
select is(
    (
        select prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'mainEventID'::uuid,
            :'ticketTypeAID'::uuid,
            :'platformFeeUserID'::uuid,
            null,
            'stripe',
            null,
            null,
            250
        )::jsonb->>'provisional_platform_fee_amount_minor'
    ),
    '62',
    'Should snapshot the platform fee from the final amount rounding down'
);

-- Should persist the platform fee snapshot on the pending purchase
select results_eq(
    format(
        $$
        select provisional_platform_fee_amount_minor
        from event_purchase
        where event_id = %L::uuid
        and user_id = %L::uuid
        $$,
        :'mainEventID',
        :'platformFeeUserID'
    ),
    $$ values (62::bigint) $$,
    'Should persist the platform fee snapshot on the pending purchase'
);

-- Should retain the original platform fee snapshot when reusing a purchase
select is(
    (
        select prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'mainEventID'::uuid,
            :'ticketTypeAID'::uuid,
            :'platformFeeUserID'::uuid,
            null,
            'stripe',
            null,
            null,
            500
        )::jsonb->>'provisional_platform_fee_amount_minor'
    ),
    '62',
    'Should retain the original platform fee snapshot when reusing a purchase'
);

-- Should reject a platform fee that consumes the full amount
select throws_ok(
    format($$select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe',
            null,
            null,
            10000
        )$$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'platformFeeMaxUserID'
    ),
    'P0001',
    'platform fee basis points must be between 0 and 9999',
    'Should reject a platform fee that consumes the full amount'
);

-- Should reject negative platform fee basis points
select throws_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe',
            null,
            null,
            -1
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'platformFeeUserID'
    ),
    'P0001',
    'platform fee basis points must be between 0 and 9999',
    'Should reject negative platform fee basis points'
);

-- Should reject checkout for an unpublished event
select throws_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe'
        )
        $$,
        :'communityID',
        :'unpublishedEventID',
        :'ticketTypeAID',
        :'checkoutUserID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject checkout for an unpublished event'
);

-- Should reuse an equivalent pending purchase after registration closes
select is(
    (
        select prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'closedWindowEventID'::uuid,
            :'closedWindowTicketTypeAID'::uuid,
            :'closedWindowMatchingUserID'::uuid,
            null,
            'stripe'
        )::jsonb->>'event_purchase_id'
    ),
    :'closedWindowMatchingPurchaseID',
    'Should reuse an equivalent pending purchase after registration closes'
);

-- Should reject replacing a pending purchase after registration closes
select throws_ok(
    format($$select prepare_event_checkout_purchase(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null,
        'stripe'
    )$$,
        :'communityID',
        :'closedWindowEventID',
        :'closedWindowTicketTypeBID',
        :'closedWindowMismatchedUserID'
    ),
    'OCG01',
    'event registration is not open',
    'Should reject replacing a pending purchase after registration closes'
);

-- Should reject creating a checkout purchase after registration closes
select throws_ok(
    format($$select prepare_event_checkout_purchase(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null,
        'stripe'
    )$$,
        :'communityID',
        :'closedWindowEventID',
        :'closedWindowTicketTypeAID',
        :'closedWindowNewUserID'
    ),
    'OCG01',
    'event registration is not open',
    'Should reject creating a checkout purchase after registration closes'
);

-- Should reuse an equivalent pending purchase when the ticket type is sold out
select is(
    (
        select prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'soldOutEventID'::uuid,
            :'soldOutTicketTypeID'::uuid,
            :'soldOutPendingUserID'::uuid,
            null,
            'stripe'
        )::jsonb->>'event_purchase_id'
    ),
    :'soldOutPendingPurchaseID',
    'Should reuse an equivalent pending purchase when the ticket type is sold out'
);

-- Should preserve a payment-blocked queue head over discounted direct checkout
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'queueEventID'::uuid,
        :'queueTicketTypeID'::uuid,
        :'queueCheckoutUserID'::uuid,
        'QUEUEFREE',
        null
    ),
    '{"conflict":"ticket-type-sold-out"}'::jsonb,
    'Should preserve a payment-blocked queue head over discounted direct checkout'
);

-- Should preserve FIFO queue priority over direct checkout
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'queueEventID'::uuid,
        :'queueTicketTypeID'::uuid,
        :'queueCheckoutUserID'::uuid,
        null,
        'stripe'
    ),
    '{"conflict":"ticket-type-sold-out"}'::jsonb,
    'Should preserve FIFO queue priority over direct checkout'
);

-- Should persist reconciliation before rejecting direct checkout
select is(
    (
        select jsonb_build_object(
            'offer_status', (
                select status
                from admission_offer
                where event_id = :'queueEventID'::uuid
                and user_id = :'queueUserID'::uuid
            ),
            'purchase_status', (
                select status
                from event_purchase
                where event_purchase_id = :'queueExpiredPurchaseID'::uuid
            ),
            'waitlist_count', (
                select count(*)
                from event_waitlist
                where event_id = :'queueEventID'::uuid
            )
        )
    ),
    '{"offer_status":"pending","purchase_status":"expired","waitlist_count":0}'::jsonb,
    'Should persist reconciliation before rejecting direct checkout'
);

-- Should reject claiming an offer owned by another user
select is(
    prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'mainEventID'::uuid,
            :'offerPrivateTicketTypeID'::uuid,
            :'offerWrongUserID'::uuid,
            null,
            'stripe',
            null,
            :'offerPaidID'::uuid
    ),
    '{"conflict":"admission-offer-unavailable"}'::jsonb,
    'Should reject claiming an offer owned by another user'
);

-- Should prepare paid checkout for an invitation-only offer
select lives_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'freepass',
            'stripe',
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'offerPrivateTicketTypeID',
        :'offerPaidUserID',
        :'offerPaidID'
    ),
    'Should prepare paid checkout for an invitation-only offer'
);

-- Should require the offer checkout path while its linked hold remains active
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'mainEventID'::uuid,
        :'offerPrivateTicketTypeID'::uuid,
        :'offerPaidUserID'::uuid,
        null,
        'stripe'
    ),
    '{"conflict":"admission-offer-required"}'::jsonb,
    'Should require the offer checkout path while its linked hold remains active'
);

-- Should snapshot and link the paid offer checkout
select results_eq(
    format(
        $$
        select
            ao.amount_minor,
            ao.currency_code,
            ao.discount_amount_minor,
            ao.discount_code,
            ao.status,
            ep.admission_offer_id,
            ep.amount_minor,
            ep.discount_code,
            ep.status
        from admission_offer ao
        join event_purchase ep using (admission_offer_id)
        where ao.admission_offer_id = %L::uuid
        $$,
        :'offerPaidID'
    ),
    format(
        $$
        values (
            500::bigint,
            'USD'::text,
            2500::bigint,
            'FREEPASS'::text,
            'checkout_pending'::text,
            %L::uuid,
            500::bigint,
            'FREEPASS'::text,
            'pending'::text
        )
        $$,
        :'offerPaidID'
    ),
    'Should snapshot and link the paid offer checkout'
);

-- Should reuse the pending checkout for the same offer
select is(
    (
        select prepare_event_checkout_purchase(
            :'communityID'::uuid,
            :'mainEventID'::uuid,
            :'offerPrivateTicketTypeID'::uuid,
            :'offerPaidUserID'::uuid,
            null,
            'stripe',
            null,
            :'offerPaidID'::uuid
        )->>'event_purchase_id'
    ),
    (
        select event_purchase_id::text
        from event_purchase
        where admission_offer_id = :'offerPaidID'::uuid
    ),
    'Should reuse the pending checkout for the same offer'
);

-- Should cancel the first offer-linked checkout
select lives_ok(
    format(
        $$ select cancel_event_checkout(%L, %L, %L, 'stripe') $$,
        :'communityID',
        :'mainEventID',
        :'offerPaidUserID'
    ),
    'Should cancel the first offer-linked checkout'
);

-- Raise the invitation tier price between the first offer claim and its retry
update event_ticket_price_window
set amount_minor = 5000
where event_ticket_price_window_id = :'offerPrivatePriceWindowID'::uuid;

-- Should retry checkout through the same offer
select lives_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe',
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'offerPrivateTicketTypeID',
        :'offerPaidUserID',
        :'offerPaidID'
    ),
    'Should retry checkout through the same offer'
);

-- Should copy the immutable first claim snapshot into every retry purchase
select results_eq(
    format(
        $$
        select
            ao.amount_minor,
            current_price.amount_minor,
            count(*) filter (where ep.status = 'expired')::int,
            count(*) filter (where ep.status = 'pending')::int,
            min(ep.amount_minor),
            max(ep.amount_minor)
        from admission_offer ao
        join event_purchase ep using (admission_offer_id)
        join event_ticket_price_window current_price
            on current_price.event_ticket_type_id = ao.event_ticket_type_id
        where ao.admission_offer_id = %L::uuid
        group by ao.amount_minor, current_price.amount_minor
        $$,
        :'offerPaidID'
    ),
    $$ values (500::bigint, 5000::bigint, 1, 1, 500::bigint, 500::bigint) $$,
    'Should copy the immutable first claim snapshot into every retry purchase'
);

-- Should reject changing the offer discount selection on retry
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'mainEventID'::uuid,
        :'offerPrivateTicketTypeID'::uuid,
        :'offerPaidUserID'::uuid,
        'total1',
        'stripe',
        null,
        :'offerPaidID'::uuid
    ),
    '{"conflict":"admission-offer-price-locked"}'::jsonb,
    'Should reject changing the offer discount selection on retry'
);

-- Should reject offer discounts below one minor unit
select throws_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'tiny25',
            'stripe',
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'ineffectiveDiscountTicketTypeID',
        :'ineffectiveDiscountUserID',
        :'ineffectiveDiscountOfferID'
    ),
    'OCG01',
    'discount code does not reduce ticket price',
    'Should reject offer discounts below one minor unit'
);

-- Should prepare a discounted-to-zero offer claim
select lives_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'freepass',
            null,
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'offerDiscountUserID',
        :'offerDiscountID'
    ),
    'Should prepare a discounted-to-zero offer claim'
);

-- Should retain discounted-to-zero offer price snapshots
select results_eq(
    format(
        $$
        select
            ao.amount_minor,
            ao.currency_code,
            ao.discount_amount_minor,
            ao.discount_code,
            ep.amount_minor,
            ep.currency_code,
            ep.provider_tax_code
        from admission_offer ao
        join event_purchase ep using (admission_offer_id)
        where ao.admission_offer_id = %L::uuid
        $$,
        :'offerDiscountID'
    ),
    $$ values (
        0::bigint,
        'USD'::text,
        2500::bigint,
        'FREEPASS'::text,
        0::bigint,
        'USD'::text,
        null::text
    ) $$,
    'Should retain discounted-to-zero offer price snapshots'
);

-- Should cancel the discounted-to-zero offer checkout
select lives_ok(
    format(
        $$ select cancel_event_checkout(%L, %L, %L, null) $$,
        :'communityID',
        :'mainEventID',
        :'offerDiscountUserID'
    ),
    'Should cancel the discounted-to-zero offer checkout'
);

-- Should retry the discounted-to-zero offer without resubmitting its code
select lives_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            null,
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'offerDiscountUserID',
        :'offerDiscountID'
    ),
    'Should retry the discounted-to-zero offer without resubmitting its code'
);

-- Should reuse the discounted-to-zero offer snapshot for its retry purchase
select results_eq(
    format(
        $$
        select
            count(*) filter (where ep.status = 'expired')::int,
            count(*) filter (where ep.status = 'pending')::int,
            bool_and(ep.discount_code = 'FREEPASS'),
            min(ep.amount_minor),
            max(ep.amount_minor)
        from event_purchase ep
        where ep.admission_offer_id = %L::uuid
        $$,
        :'offerDiscountID'
    ),
    $$ values (1, 1, true, 0::bigint, 0::bigint) $$,
    'Should reuse the discounted-to-zero offer snapshot for its retry purchase'
);

-- Should prepare an intrinsic-free offer claim
select lives_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            null,
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'freeEventID',
        :'freeTicketTypeID',
        :'offerFreeUserID',
        :'offerFreeID'
    ),
    'Should prepare an intrinsic-free offer claim'
);

-- Should retain intrinsic-free offer price snapshots
select results_eq(
    format(
        $$
        select
            ao.amount_minor,
            ao.currency_code,
            ao.status,
            ep.amount_minor,
            ep.currency_code,
            ep.provider_tax_code
        from admission_offer ao
        join event_purchase ep using (admission_offer_id)
        where ao.admission_offer_id = %L::uuid
        $$,
        :'offerFreeID'
    ),
    $$ values (
        0::bigint,
        null::text,
        'checkout_pending'::text,
        0::bigint,
        null::text,
        null::text
    ) $$,
    'Should retain intrinsic-free offer price snapshots'
);

-- Should apply a valid discount
select lives_ok(
    format(
        $$
            select prepare_event_checkout_purchase(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                'freepass',
                null
            )
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'discountUserID'
    ),
    'Should apply a valid discount'
);

-- Should persist discounted-to-zero snapshots and decrement availability
select results_eq(
    format(
        $$
            select
                (
                    select amount_minor::text
                    from event_purchase
                    where event_id = %1$L::uuid
                    and user_id = %2$L::uuid
                    and status = 'pending'
                ),
                (
                    select currency_code
                    from event_purchase
                    where event_id = %1$L::uuid
                    and user_id = %2$L::uuid
                    and status = 'pending'
                ),
                (
                    select discount_amount_minor::text
                    from event_purchase
                    where event_id = %1$L::uuid
                    and user_id = %2$L::uuid
                    and status = 'pending'
                ),
                (
                    select available::text
                    from event_discount_code
                    where event_discount_code_id = %3$L::uuid
                )
        $$,
        :'mainEventID',
        :'discountUserID',
        :'freeDiscountID'
    ),
    $$ values ('0'::text, 'USD'::text, '2500'::text, '1'::text) $$,
    'Should persist discounted-to-zero snapshots and decrement availability'
);

-- Should reject discounted checkout amounts below Stripe minimums
select throws_ok(
    format(
        $$
            select prepare_event_checkout_purchase(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                'UNDERMIN',
                'stripe'
            )
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'underMinimumUserID'
    ),
    'OCG01',
    'payment amount must be zero or at least Stripe minimum charge amount',
    'Should reject discounted checkout amounts below Stripe minimums'
);

-- Should require answers before preparing checkout for events with questions
select throws_ok(
    format(
        $$
            select prepare_event_checkout_purchase(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                null,
                'stripe'
            )
        $$,
        :'communityID',
        :'questionsEventID',
        :'questionsTicketTypeID',
        :'questionsUserID'
    ),
    'OCG01',
    'questionnaire answers are required',
    'Should require answers before preparing checkout for events with questions'
);

-- Should prepare checkout when registration answers are provided
select lives_ok(
    format(
        $$
            select prepare_event_checkout_purchase(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                null,
                'stripe',
                %L::jsonb
            )
        $$,
        :'communityID',
        :'questionsEventID',
        :'questionsTicketTypeID',
        :'questionsUserID',
        jsonb_build_object('answers', jsonb_build_array(jsonb_build_object(
            'question_id', :'registrationQuestionID',
            'value', 'Checkout answer'
        )))
    ),
    'Should prepare checkout when registration answers are provided'
);

-- Should store checkout registration answers in a pending attendee row
select results_eq(
    format(
        $$
            select status, registration_answers
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'questionsEventID',
        :'questionsUserID'
    ),
    format(
        $$ values ('registration-questions-pending'::text, %L::jsonb) $$,
        jsonb_build_object('answers', jsonb_build_array(jsonb_build_object(
            'question_id', :'registrationQuestionID',
            'value', 'Checkout answer'
        )))
    ),
    'Should store checkout registration answers in a pending attendee row'
);

-- Should reject reusing a pending purchase when an invitation is pending
select throws_ok(
    format(
        $$
            select prepare_event_checkout_purchase(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                null,
                'stripe'
            )
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'invitedUserID'
    ),
    'OCG01',
    'user has a pending or rejected invitation for this event',
    'Should reject reusing a pending purchase when an invitation is pending'
);

-- Should return a typed conflict for an inactive ticket type
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'inactiveEventID'::uuid,
        :'inactiveTicketTypeID'::uuid,
        :'inactiveUserID'::uuid,
        null,
        'stripe'
    ),
    '{"conflict":"ticket-type-inactive"}'::jsonb,
    'Should return a typed conflict for an inactive ticket type'
);

-- Should return a typed conflict for a ticket type owned by another event
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'mainEventID'::uuid,
        :'freeTicketTypeID'::uuid,
        :'staleTicketUserID'::uuid,
        null,
        'stripe'
    ),
    '{"conflict":"ticket-type-unavailable"}'::jsonb,
    'Should return a typed conflict for a ticket type owned by another event'
);

-- Should not create a purchase for a ticket type owned by another event
select is(
    (
        select count(*)::int
        from event_purchase ep
        where ep.event_id = :'mainEventID'::uuid
        and ep.user_id = :'staleTicketUserID'::uuid
    ),
    0,
    'Should not create a purchase for a ticket type owned by another event'
);

-- Should return a typed conflict when a ticket type has no current price
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'priceUnavailableEventID'::uuid,
        :'priceUnavailableTicketTypeID'::uuid,
        :'priceUnavailableUserID'::uuid,
        null,
        'stripe'
    ),
    '{"conflict":"ticket-type-price-unavailable"}'::jsonb,
    'Should return a typed conflict when a ticket type has no current price'
);

-- Should return a typed conflict when paid checkout setup is unavailable
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'paymentSetupUnavailableEventID'::uuid,
        :'paymentSetupUnavailableTicketTypeID'::uuid,
        :'paymentSetupUnavailableUserID'::uuid,
        null,
        null
    ),
    '{"conflict":"payment-setup-unavailable"}'::jsonb,
    'Should return a typed conflict when paid checkout setup is unavailable'
);

-- Should return matching immutable account-scoped automatic-tax resources
select results_eq(
    format($$
        with prepared as (
            select prepare_event_checkout_purchase(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                null,
                'stripe'
            ) as value
        )
        select
            value->>'cached_provider_tax_location_id',
            value->>'cached_provider_tax_product_id',
            value->>'cached_performance_location_fingerprint' = (
                select fingerprint
                from payment_provider_tax_location
                where provider_tax_location_id = 'loc_cached'
            ),
            value->>'cached_product_fingerprint' = (
                select fingerprint
                from payment_provider_tax_product
                where provider_tax_product_id = 'prod_cached'
            )
        from prepared
    $$, :'communityID', :'mainEventID', :'ticketTypeAID', :'cacheUserID'),
    $$ values ('loc_cached'::text, 'prod_cached'::text, true, true) $$,
    'Should return matching immutable account-scoped automatic-tax resources'
);

-- Should prepare a manual-tax purchase
select lives_ok(
    format($$select prepare_event_checkout_purchase(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null,
        'stripe'
    )$$,
        :'communityID',
        :'manualTaxEventID',
        :'manualTaxTicketTypeID',
        :'manualTaxUserID'
    ),
    'Should prepare a manual-tax purchase'
);

-- Should snapshot every event-level manual Tax Rate identifier
select results_eq(
    format($$
        select
            manual_tax_rate_ids,
            tax_calculation_mode
        from event_purchase
        where event_id = %L::uuid
        and user_id = %L::uuid
        and status = 'pending'
    $$, :'manualTaxEventID', :'manualTaxUserID'),
    $$ values (array['txr_state', 'txr_local']::text[], 'manual'::text) $$,
    'Should snapshot every event-level manual Tax Rate identifier'
);

-- Should apply a live-window discount over an issue-time offer snapshot
select lives_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'freepass',
            'stripe',
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'mainEventID',
        :'ticketTypeAID',
        :'liveSnapshotUserID',
        :'liveSnapshotOfferID'
    ),
    'Should apply a live-window discount over an issue-time offer snapshot'
);

-- Should overwrite the issue snapshot with the claimed live price
select results_eq(
    format(
        $$
        select
            ao.amount_minor,
            ao.currency_code,
            ao.discount_amount_minor,
            ao.discount_code,
            ao.status
        from admission_offer ao
        where ao.admission_offer_id = %L::uuid
        $$,
        :'liveSnapshotOfferID'
    ),
    $$ values (
        0::bigint,
        'USD'::text,
        2500::bigint,
        'FREEPASS'::text,
        'checkout_pending'::text
    ) $$,
    'Should overwrite the issue snapshot with the claimed live price'
);

-- Should claim a snapshotted offer after its price window ends
select lives_ok(
    format(
        $$
        select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe',
            null,
            %L::uuid
        )
        $$,
        :'communityID',
        :'priceUnavailableEventID',
        :'priceUnavailableTicketTypeID',
        :'endedWindowUserID',
        :'endedWindowOfferID'
    ),
    'Should claim a snapshotted offer after its price window ends'
);

-- Should keep the stored price when claiming after the window ends
select results_eq(
    format(
        $$
        select
            ao.amount_minor,
            ao.currency_code,
            ao.status,
            ep.amount_minor
        from admission_offer ao
        join event_purchase ep using (admission_offer_id)
        where ao.admission_offer_id = %L::uuid
        $$,
        :'endedWindowOfferID'
    ),
    $$ values (
        2500::bigint,
        'USD'::text,
        'checkout_pending'::text,
        2500::bigint
    ) $$,
    'Should keep the stored price when claiming after the window ends'
);

-- Should reject a new discount code when falling back to the stored price
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'priceUnavailableEventID'::uuid,
        :'priceUnavailableTicketTypeID'::uuid,
        :'endedWindowDiscountUserID'::uuid,
        'freepass',
        'stripe',
        null,
        :'endedWindowDiscountOfferID'::uuid
    ),
    '{"conflict":"admission-offer-price-locked"}'::jsonb,
    'Should reject a new discount code when falling back to the stored price'
);

-- Should require a live price window for waitlist claims after sales end
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'priceUnavailableEventID'::uuid,
        :'priceUnavailableTicketTypeID'::uuid,
        :'endedWindowWaitlistUserID'::uuid,
        null,
        'stripe',
        null,
        :'endedWindowWaitlistOfferID'::uuid
    ),
    '{"conflict":"ticket-type-price-unavailable"}'::jsonb,
    'Should require a live price window for waitlist claims after sales end'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
