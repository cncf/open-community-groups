-- Tests releasing active admission offers as canceled or declined.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set checkoutOfferID 'a1ea0000-0000-0000-0000-000000000001'
\set checkoutPurchaseID 'a1ea0000-0000-0000-0000-000000000002'
\set checkoutUserID 'a1ea0000-0000-0000-0000-000000000003'
\set communityID 'a1ea0000-0000-0000-0000-000000000004'
\set declinedOfferID 'a1ea0000-0000-0000-0000-000000000005'
\set declinedUserID 'a1ea0000-0000-0000-0000-000000000006'
\set eventCategoryID 'a1ea0000-0000-0000-0000-000000000007'
\set eventID 'a1ea0000-0000-0000-0000-000000000008'
\set groupCategoryID 'a1ea0000-0000-0000-0000-000000000009'
\set groupID 'a1ea0000-0000-0000-0000-000000000010'
\set lapsedOfferID 'a1ea0000-0000-0000-0000-000000000011'
\set lapsedUserID 'a1ea0000-0000-0000-0000-000000000012'
\set otherEventID 'a1ea0000-0000-0000-0000-000000000013'
\set otherEventOfferID 'a1ea0000-0000-0000-0000-000000000014'
\set otherEventPriceWindowID 'a1ea0000-0000-0000-0000-000000000015'
\set otherEventTicketTypeID 'a1ea0000-0000-0000-0000-000000000016'
\set otherEventUserID 'a1ea0000-0000-0000-0000-000000000017'
\set otherUserID 'a1ea0000-0000-0000-0000-000000000018'
\set ownedOfferID 'a1ea0000-0000-0000-0000-000000000029'
\set ownerUserID 'a1ea0000-0000-0000-0000-000000000030'
\set pendingOfferID 'a1ea0000-0000-0000-0000-000000000019'
\set pendingUserID 'a1ea0000-0000-0000-0000-000000000020'
\set priceWindowID 'a1ea0000-0000-0000-0000-000000000021'
\set ticketTypeID 'a1ea0000-0000-0000-0000-000000000022'
\set waitlistEventID 'a1ea0000-0000-0000-0000-000000000023'
\set waitlistHeadUserID 'a1ea0000-0000-0000-0000-000000000024'
\set waitlistOfferID 'a1ea0000-0000-0000-0000-000000000025'
\set waitlistOfferUserID 'a1ea0000-0000-0000-0000-000000000026'
\set waitlistPriceWindowID 'a1ea0000-0000-0000-0000-000000000027'
\set waitlistTicketTypeID 'a1ea0000-0000-0000-0000-000000000028'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the offer events
select fx_community(:'communityID');

-- User whose checkout-pending offer is declined
select fx_user(:'checkoutUserID');

-- User whose offer was already declined
select fx_user(:'declinedUserID');

-- User whose pending offer passed its deadline
select fx_user(:'lapsedUserID');

-- User whose live offer belongs to another event
select fx_user(:'otherEventUserID');

-- User who does not own the pending offer
select fx_user(:'otherUserID');

-- User owning the live offer that guard scenarios leave untouched
select fx_user(:'ownerUserID');

-- User whose pending offer is canceled
select fx_user(:'pendingUserID');

-- User at the head of the waitlist promoted into the released seat
select fx_user(:'waitlistHeadUserID');

-- User whose offer holds the only seat of the waitlist tier
select fx_user(:'waitlistOfferUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the offer events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Published event owning the offers released by the scenarios
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published event owning a live offer outside the released event
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published event with an open registration window and a waitlist
select fx_event(:'waitlistEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'registration_ends_at', current_timestamp + interval '1 day',
    'registration_starts_at', current_timestamp - interval '1 day',
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Ticket tier of the other event
select fx_event_ticket_type(:'otherEventTicketTypeID', :'otherEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'Other admission'
));

-- Ticket tier reserved by the released offers
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Single-seat public tier whose released seat refills from the waitlist
select fx_event_ticket_type(:'waitlistTicketTypeID', :'waitlistEventID', jsonb_build_object(
    'availability', 'public',
    'seats_total', 1,
    'title', 'Waitlist admission'
));

-- Live offers, a lapsed offer and a terminal offer used by the scenarios
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id,

    amount_minor,
    discount_amount_minor,
    ticket_title
) values (
    :'checkoutOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'waitlist',
    'checkout_pending',
    :'checkoutUserID',

    0,
    0,
    'General admission'
), (
    :'declinedOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'waitlist',
    'declined',
    :'declinedUserID',

    null,
    null,
    null
), (
    :'lapsedOfferID',
    current_timestamp - interval '2 hours',
    :'eventID',
    :'ticketTypeID',
    current_timestamp - interval '1 hour',
    'waitlist',
    'pending',
    :'lapsedUserID',

    null,
    null,
    null
), (
    :'otherEventOfferID',
    current_timestamp,
    :'otherEventID',
    :'otherEventTicketTypeID',
    current_timestamp + interval '1 hour',
    'waitlist',
    'pending',
    :'otherEventUserID',

    null,
    null,
    null
), (
    :'ownedOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'waitlist',
    'pending',
    :'ownerUserID',

    null,
    null,
    null
), (
    :'pendingOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'waitlist',
    'pending',
    :'pendingUserID',

    null,
    null,
    null
), (
    :'waitlistOfferID',
    current_timestamp,
    :'waitlistEventID',
    :'waitlistTicketTypeID',
    current_timestamp + interval '1 hour',
    'waitlist',
    'pending',
    :'waitlistOfferUserID',

    null,
    null,
    null
);

-- Free price window of the other event tier
select fx_event_ticket_price_window(:'otherEventPriceWindowID', :'otherEventTicketTypeID', jsonb_build_object(
    'amount_minor', 0
));

-- Free price window of the released event tier
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object(
    'amount_minor', 0
));

-- Free price window that lets the waitlist head be promoted
select fx_event_ticket_price_window(:'waitlistPriceWindowID', :'waitlistTicketTypeID', jsonb_build_object(
    'amount_minor', 0
));

-- Waitlist head queued behind the full single-seat tier
insert into event_waitlist (
    created_at,
    event_id,
    event_ticket_type_id,
    user_id
) values (
    current_timestamp - interval '1 hour',
    :'waitlistEventID',
    :'waitlistTicketTypeID',
    :'waitlistHeadUserID'
);

-- Pending checkout linked to the checkout-pending offer
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'checkoutOfferID',
    0,
    'USD',
    0,
    :'eventID',
    :'checkoutPurchaseID',
    :'ticketTypeID',
    current_timestamp + interval '15 minutes',
    'pending',
    'General admission',
    :'checkoutUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel a pending offer and return the updated row
select results_eq(
    format(
        $$
        select admission_offer_id, status
        from release_event_admission_offer(%L, %L, %L, %L, 'canceled', null)
        $$,
        :'eventID',
        :'ticketTypeID',
        :'pendingUserID',
        :'pendingOfferID'
    ),
    format(
        $$ values (%L::uuid, 'canceled'::text) $$,
        :'pendingOfferID'
    ),
    'Should cancel a pending offer and return the updated row'
);

-- Should persist the canceled offer status
select is(
    (select status from admission_offer where admission_offer_id = :'pendingOfferID'),
    'canceled',
    'Should persist the canceled offer status'
);

-- Should decline a checkout-pending offer
select lives_ok(
    format(
        $$ select release_event_admission_offer(%L, %L, %L, %L, 'declined', null) $$,
        :'eventID',
        :'ticketTypeID',
        :'checkoutUserID',
        :'checkoutOfferID'
    ),
    'Should decline a checkout-pending offer'
);

-- Should expire the linked checkout and store the decline
select results_eq(
    format(
        $$
        select
            (select status from admission_offer where admission_offer_id = %L::uuid),
            (select status from event_purchase where event_purchase_id = %L::uuid)
        $$,
        :'checkoutOfferID',
        :'checkoutPurchaseID'
    ),
    $$ values ('declined'::text, 'expired'::text) $$,
    'Should expire the linked checkout and store the decline'
);

-- Should refill the released seat from the tier waitlist
select lives_ok(
    format(
        $$ select release_event_admission_offer(%L, %L, %L, %L, 'canceled', null) $$,
        :'waitlistEventID',
        :'waitlistTicketTypeID',
        :'waitlistOfferUserID',
        :'waitlistOfferID'
    ),
    'Should refill the released seat from the tier waitlist'
);

-- Should promote the waitlist head into a pending offer for the released tier
select ok(
    exists (
        select 1
        from admission_offer ao
        where ao.event_id = :'waitlistEventID'
        and ao.event_ticket_type_id = :'waitlistTicketTypeID'
        and ao.source = 'waitlist'
        and ao.status = 'pending'
        and ao.user_id = :'waitlistHeadUserID'
    )
    and not exists (
        select 1
        from event_waitlist ew
        where ew.event_id = :'waitlistEventID'
        and ew.user_id = :'waitlistHeadUserID'
    ),
    'Should promote the waitlist head into a pending offer for the released tier'
);

-- Should reject a lapsed offer
select throws_ok(
    format(
        $$ select release_event_admission_offer(%L, %L, %L, %L, 'declined', null) $$,
        :'eventID',
        :'ticketTypeID',
        :'lapsedUserID',
        :'lapsedOfferID'
    ),
    'OCG01',
    'admission offer is no longer available',
    'Should reject a lapsed offer'
);

-- Should reject a null release status
select throws_ok(
    format(
        $$ select release_event_admission_offer(%L, %L, %L, %L, null, null) $$,
        :'eventID',
        :'ticketTypeID',
        :'ownerUserID',
        :'ownedOfferID'
    ),
    'P0001',
    'invalid admission offer release status: <NULL>',
    'Should reject a null release status'
);

-- Should reject a release status other than canceled or declined
select throws_ok(
    format(
        $$ select release_event_admission_offer(%L, %L, %L, %L, 'expired', null) $$,
        :'eventID',
        :'ticketTypeID',
        :'ownerUserID',
        :'ownedOfferID'
    ),
    'P0001',
    'invalid admission offer release status: expired',
    'Should reject a release status other than canceled or declined'
);

-- Should reject a terminal offer
select throws_ok(
    format(
        $$ select release_event_admission_offer(%L, %L, %L, %L, 'declined', null) $$,
        :'eventID',
        :'ticketTypeID',
        :'declinedUserID',
        :'declinedOfferID'
    ),
    'OCG01',
    'admission offer is no longer available',
    'Should reject a terminal offer'
);

-- Should reject another event's offer
select throws_ok(
    format(
        $$ select release_event_admission_offer(%L, %L, %L, %L, 'declined', null) $$,
        :'eventID',
        :'ticketTypeID',
        :'otherEventUserID',
        :'otherEventOfferID'
    ),
    'OCG01',
    'admission offer is no longer available',
    'Should reject another event''s offer'
);

-- Should reject another user's offer
select throws_ok(
    format(
        $$ select release_event_admission_offer(%L, %L, %L, %L, 'declined', null) $$,
        :'eventID',
        :'ticketTypeID',
        :'otherUserID',
        :'ownedOfferID'
    ),
    'OCG01',
    'admission offer is no longer available',
    'Should reject another user''s offer'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
