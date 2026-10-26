-- Tests resolving the price shown for an admission offer.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set checkoutPendingOfferID 'f3110000-0000-0000-0000-000000000001'
\set checkoutPendingUserID 'f3110000-0000-0000-0000-000000000002'
\set communityID 'f3110000-0000-0000-0000-000000000003'
\set declinedOfferID 'f3110000-0000-0000-0000-00000000001e'
\set declinedUserID 'f3110000-0000-0000-0000-00000000001f'
\set discountCodeID 'f3110000-0000-0000-0000-000000000004'
\set discountedOfferID 'f3110000-0000-0000-0000-000000000005'
\set discountedUserID 'f3110000-0000-0000-0000-000000000006'
\set endedApprovalOfferID 'f3110000-0000-0000-0000-000000000007'
\set endedApprovalUserID 'f3110000-0000-0000-0000-000000000008'
\set endedEventID 'f3110000-0000-0000-0000-000000000009'
\set endedOrganizerOfferID 'f3110000-0000-0000-0000-00000000001c'
\set endedOrganizerUserID 'f3110000-0000-0000-0000-00000000001d'
\set endedPriceWindowID 'f3110000-0000-0000-0000-00000000000a'
\set endedTicketTypeID 'f3110000-0000-0000-0000-00000000000b'
\set endedWaitlistOfferID 'f3110000-0000-0000-0000-00000000000c'
\set endedWaitlistUserID 'f3110000-0000-0000-0000-00000000000d'
\set eventCategoryID 'f3110000-0000-0000-0000-00000000000e'
\set eventID 'f3110000-0000-0000-0000-00000000000f'
\set freeOfferID 'f3110000-0000-0000-0000-000000000010'
\set freePriceWindowID 'f3110000-0000-0000-0000-000000000011'
\set freeTicketTypeID 'f3110000-0000-0000-0000-000000000012'
\set freeUserID 'f3110000-0000-0000-0000-000000000013'
\set fullyDiscountedOfferID 'f3110000-0000-0000-0000-000000000014'
\set fullyDiscountedUserID 'f3110000-0000-0000-0000-000000000015'
\set groupCategoryID 'f3110000-0000-0000-0000-000000000016'
\set groupID 'f3110000-0000-0000-0000-000000000017'
\set livePriceOfferID 'f3110000-0000-0000-0000-000000000018'
\set livePriceUserID 'f3110000-0000-0000-0000-000000000019'
\set paidPriceWindowID 'f3110000-0000-0000-0000-00000000001a'
\set paidTicketTypeID 'f3110000-0000-0000-0000-00000000001b'
\set stalePaidOfferID 'f3110000-0000-0000-0000-000000000020'
\set stalePaidUserID 'f3110000-0000-0000-0000-000000000021'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group and offer recipients
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'checkoutPendingUserID');
select fx_user(:'declinedUserID');
select fx_user(:'discountedUserID');
select fx_user(:'endedApprovalUserID');
select fx_user(:'endedOrganizerUserID');
select fx_user(:'endedWaitlistUserID');
select fx_user(:'freeUserID');
select fx_user(:'fullyDiscountedUserID');
select fx_user(:'livePriceUserID');
select fx_user(:'stalePaidUserID');

-- Event charged in EUR whose ticket sales window has ended
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('payment_currency_code', 'EUR'));

-- Event charged in USD with open paid and free ticket tiers
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('payment_currency_code', 'USD'));

-- Discount applied by the discounted offers
insert into event_discount_code (event_discount_code_id, amount_minor, code, event_id, kind, title)
values (:'discountCodeID', 1000, 'DISPLAY10', :'eventID', 'fixed_amount', 'Display save');

-- Ticket tier whose only price window has ended
select fx_event_ticket_type(:'endedTicketTypeID', :'endedEventID', jsonb_build_object('title', 'Ended admission'));

-- Free ticket tier with an open price window
select fx_event_ticket_type(:'freeTicketTypeID', :'eventID', jsonb_build_object(
    'order', 2,
    'title', 'Free admission'
));

-- Paid ticket tier with an open price window
select fx_event_ticket_type(:'paidTicketTypeID', :'eventID', jsonb_build_object('title', 'Paid admission'));

-- Pending approval offer whose snapshot is taken after sales end
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'endedApprovalOfferID',
    2500,
    'USD',
    0,
    :'endedEventID',
    :'endedTicketTypeID',
    '2099-01-01 00:00:00+00',
    'approval',
    'pending',
    'Ended admission',
    :'endedApprovalUserID'
);

-- Pending organizer invitation whose snapshot is taken after sales end
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'endedOrganizerOfferID',
    2500,
    'USD',
    0,
    :'endedEventID',
    :'endedTicketTypeID',
    '2099-01-01 00:00:00+00',
    'organizer_invitation',
    'pending',
    'Ended admission',
    :'endedOrganizerUserID'
);

-- Pending waitlist offer whose snapshot is ignored after sales end
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'endedWaitlistOfferID',
    2500,
    'USD',
    0,
    :'endedEventID',
    :'endedTicketTypeID',
    '2099-01-01 00:00:00+00',
    'waitlist',
    'pending',
    'Ended admission',
    :'endedWaitlistUserID'
);

-- Checkout-pending offer whose snapshot is below the live price
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'checkoutPendingOfferID',
    1000,
    'USD',
    0,
    :'eventID',
    :'paidTicketTypeID',
    '2099-01-01 00:00:00+00',
    'approval',
    'checkout_pending',
    'Paid admission',
    :'checkoutPendingUserID'
);

-- Declined approval offer without a snapshot on the paid tier
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'declinedOfferID',
    :'eventID',
    :'paidTicketTypeID',
    '2099-01-01 00:00:00+00',
    'approval',
    'declined',
    :'declinedUserID'
);

-- Pending offer with a discounted snapshot frozen after an abandoned checkout
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
) values (
    :'discountedOfferID',
    500,
    'USD',
    1000,
    'DISPLAY10',
    :'discountCodeID',
    :'eventID',
    :'paidTicketTypeID',
    '2099-01-01 00:00:00+00',
    'approval',
    'pending',
    'Paid admission',
    :'discountedUserID'
);

-- Pending organizer invitation without a snapshot on the free tier
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'freeOfferID',
    :'eventID',
    :'freeTicketTypeID',
    '2099-01-01 00:00:00+00',
    'organizer_invitation',
    'pending',
    :'freeUserID'
);

-- Pending offer whose discount covers the whole ticket price
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
) values (
    :'fullyDiscountedOfferID',
    0,
    'USD',
    1500,
    'DISPLAY10',
    :'discountCodeID',
    :'eventID',
    :'paidTicketTypeID',
    '2099-01-01 00:00:00+00',
    'approval',
    'pending',
    'Paid admission',
    :'fullyDiscountedUserID'
);

-- Pending approval offer with a stale free snapshot on the paid tier
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'livePriceOfferID',
    0,
    null,
    0,
    :'eventID',
    :'paidTicketTypeID',
    '2099-01-01 00:00:00+00',
    'approval',
    'pending',
    'Paid admission',
    :'livePriceUserID'
);

-- Pending approval offer with a stale paid snapshot in another currency
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'stalePaidOfferID',
    1000,
    'EUR',
    0,
    :'eventID',
    :'paidTicketTypeID',
    '2099-01-01 00:00:00+00',
    'approval',
    'pending',
    'Paid admission',
    :'stalePaidUserID'
);

-- Lapsed price window of the ended ticket tier
select fx_event_ticket_price_window(:'endedPriceWindowID', :'endedTicketTypeID', jsonb_build_object(
    'amount_minor', 2500,
    'ends_at', current_timestamp - interval '1 minute',
    'starts_at', current_timestamp - interval '2 days'
));

-- Open free price window of the free ticket tier
select fx_event_ticket_price_window(:'freePriceWindowID', :'freeTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Open paid price window of the paid ticket tier
select fx_event_ticket_price_window(:'paidPriceWindowID', :'paidTicketTypeID', jsonb_build_object('amount_minor', 1500));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should hide the currency of a free pending offer
select is(
    (
        select to_jsonb(dp)
        from admission_offer ao
        join event e using (event_id)
        cross join lateral admission_offer_display_price(ao, e) dp
        where ao.admission_offer_id = :'freeOfferID'
    ),
    '{"amount_minor": 0, "currency_code": null}'::jsonb,
    'Should hide the currency of a free pending offer'
);

-- Should keep the snapshot currency of a pending approval offer after sales end
select is(
    (
        select to_jsonb(dp)
        from admission_offer ao
        join event e using (event_id)
        cross join lateral admission_offer_display_price(ao, e) dp
        where ao.admission_offer_id = :'endedApprovalOfferID'
    ),
    '{"amount_minor": 2500, "currency_code": "USD"}'::jsonb,
    'Should keep the snapshot currency of a pending approval offer after sales end'
);

-- Should keep the snapshot of a pending organizer invitation after sales end
select is(
    (
        select to_jsonb(dp)
        from admission_offer ao
        join event e using (event_id)
        cross join lateral admission_offer_display_price(ao, e) dp
        where ao.admission_offer_id = :'endedOrganizerOfferID'
    ),
    '{"amount_minor": 2500, "currency_code": "USD"}'::jsonb,
    'Should keep the snapshot of a pending organizer invitation after sales end'
);

-- Should keep the snapshot of a checkout-pending offer over the live price
select is(
    (
        select to_jsonb(dp)
        from admission_offer ao
        join event e using (event_id)
        cross join lateral admission_offer_display_price(ao, e) dp
        where ao.admission_offer_id = :'checkoutPendingOfferID'
    ),
    '{"amount_minor": 1000, "currency_code": "USD"}'::jsonb,
    'Should keep the snapshot of a checkout-pending offer over the live price'
);

-- Should keep the snapshot of a pending discounted offer
select is(
    (
        select to_jsonb(dp)
        from admission_offer ao
        join event e using (event_id)
        cross join lateral admission_offer_display_price(ao, e) dp
        where ao.admission_offer_id = :'discountedOfferID'
    ),
    '{"amount_minor": 500, "currency_code": "USD"}'::jsonb,
    'Should keep the snapshot of a pending discounted offer'
);

-- Should fall back to the live price and event currency for a non-pending offer without a snapshot
select is(
    (
        select to_jsonb(dp)
        from admission_offer ao
        join event e using (event_id)
        cross join lateral admission_offer_display_price(ao, e) dp
        where ao.admission_offer_id = :'declinedOfferID'
    ),
    '{"amount_minor": 1500, "currency_code": "USD"}'::jsonb,
    'Should fall back to the live price and event currency for a non-pending offer without a snapshot'
);

-- Should omit the snapshot of a pending waitlist offer after sales end
select is(
    (
        select to_jsonb(dp)
        from admission_offer ao
        join event e using (event_id)
        cross join lateral admission_offer_display_price(ao, e) dp
        where ao.admission_offer_id = :'endedWaitlistOfferID'
    ),
    '{"amount_minor": null, "currency_code": null}'::jsonb,
    'Should omit the snapshot of a pending waitlist offer after sales end'
);

-- Should show the currency of a fully discounted offer
select is(
    (
        select to_jsonb(dp)
        from admission_offer ao
        join event e using (event_id)
        cross join lateral admission_offer_display_price(ao, e) dp
        where ao.admission_offer_id = :'fullyDiscountedOfferID'
    ),
    '{"amount_minor": 0, "currency_code": "USD"}'::jsonb,
    'Should show the currency of a fully discounted offer'
);

-- Should use the live price and event currency for a pending offer with a stale free snapshot
select is(
    (
        select to_jsonb(dp)
        from admission_offer ao
        join event e using (event_id)
        cross join lateral admission_offer_display_price(ao, e) dp
        where ao.admission_offer_id = :'livePriceOfferID'
    ),
    '{"amount_minor": 1500, "currency_code": "USD"}'::jsonb,
    'Should use the live price and event currency for a pending offer with a stale free snapshot'
);

-- Should show the live price in the event currency over a stale paid snapshot
select is(
    (
        select to_jsonb(dp)
        from admission_offer ao
        join event e using (event_id)
        cross join lateral admission_offer_display_price(ao, e) dp
        where ao.admission_offer_id = :'stalePaidOfferID'
    ),
    '{"amount_minor": 1500, "currency_code": "USD"}'::jsonb,
    'Should show the live price in the event currency over a stale paid snapshot'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
