-- Tests seat and discount code usage counts of a ticketed event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ea060000-0000-0000-0000-000000000001'
\set discountCodeSaveID 'ea060000-0000-0000-0000-000000000002'
\set discountCodeUnusedID 'ea060000-0000-0000-0000-000000000003'
\set eventCategoryID 'ea060000-0000-0000-0000-000000000004'
\set eventID 'ea060000-0000-0000-0000-000000000005'
\set groupCategoryID 'ea060000-0000-0000-0000-000000000006'
\set groupID 'ea060000-0000-0000-0000-000000000007'
\set offerActiveID 'ea060000-0000-0000-0000-000000000008'
\set offerCheckoutID 'ea060000-0000-0000-0000-000000000009'
\set ticketTypeCompID 'ea060000-0000-0000-0000-00000000000a'
\set ticketTypeGeneralID 'ea060000-0000-0000-0000-00000000000b'
\set ticketTypeVipID 'ea060000-0000-0000-0000-00000000000c'
\set userCompletedID 'ea060000-0000-0000-0000-00000000000d'
\set userExpiredHoldID 'ea060000-0000-0000-0000-00000000000e'
\set userExpiredID 'ea060000-0000-0000-0000-00000000000f'
\set userLiveHoldID 'ea060000-0000-0000-0000-000000000010'
\set userOfferActiveID 'ea060000-0000-0000-0000-000000000011'
\set userOfferCheckoutID 'ea060000-0000-0000-0000-000000000012'
\set userRefundedID 'ea060000-0000-0000-0000-000000000013'
\set userRefundRequestedID 'ea060000-0000-0000-0000-000000000014'
\set userVipCompletedID 'ea060000-0000-0000-0000-000000000015'
\set userVipRefundPendingID 'ea060000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'userCompletedID');
select fx_user(:'userExpiredHoldID');
select fx_user(:'userExpiredID');
select fx_user(:'userLiveHoldID');
select fx_user(:'userOfferActiveID');
select fx_user(:'userOfferCheckoutID');
select fx_user(:'userRefundedID');
select fx_user(:'userRefundRequestedID');
select fx_user(:'userVipCompletedID');
select fx_user(:'userVipRefundPendingID');

-- Ticketed event whose usage is counted
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- General tickets with spare seats
select fx_event_ticket_type(:'ticketTypeGeneralID', :'eventID', jsonb_build_object(
    'order', 1,
    'seats_total', 10,
    'title', 'General'
));

-- VIP tickets oversold beyond their seats
select fx_event_ticket_type(:'ticketTypeVipID', :'eventID', jsonb_build_object(
    'order', 2,
    'seats_total', 1,
    'title', 'VIP'
));

-- Inactive complimentary tickets without seats
select fx_event_ticket_type(:'ticketTypeCompID', :'eventID', jsonb_build_object(
    'active', false,
    'order', 3,
    'seats_total', 0,
    'title', 'Comp'
));

-- Active general offers, one of them with a checkout in progress
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
    currency_code,
    discount_amount_minor,
    ticket_title
) values
    (:'offerActiveID', current_timestamp - interval '1 hour', :'eventID', :'ticketTypeGeneralID', current_timestamp + interval '1 day', 'waitlist', 'pending', :'userOfferActiveID', null, null, null, null),
    (:'offerCheckoutID', current_timestamp - interval '1 hour', :'eventID', :'ticketTypeGeneralID', current_timestamp + interval '1 day', 'approval', 'checkout_pending', :'userOfferCheckoutID', 1000, 'USD', 0, 'General');

-- Discount code with redemptions
insert into event_discount_code (
    event_discount_code_id,
    active,
    code,
    event_id,
    kind,
    title,

    available,
    percentage,
    total_available
) values (
    :'discountCodeSaveID',
    true,
    'SAVE10',
    :'eventID',
    'percentage',
    'Save ten',

    8,
    10,
    10
);

-- Inactive discount code without redemptions or limits
insert into event_discount_code (
    event_discount_code_id,
    active,
    code,
    event_id,
    kind,
    title,

    amount_minor
) values (
    :'discountCodeUnusedID',
    false,
    'UNUSED',
    :'eventID',
    'fixed_amount',
    'Unused',

    500
);

-- Purchases covering every status, discount code redemptions and an offer checkout
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    admission_offer_id,
    discount_code,
    event_discount_code_id,
    hold_expires_at
) values
    (900, 'external', 'USD', 100, :'eventID', :'ticketTypeGeneralID', 'completed', 'General', :'userCompletedID', null, 'SAVE10', :'discountCodeSaveID', null),
    (900, 'external', 'USD', 100, :'eventID', :'ticketTypeGeneralID', 'expired', 'General', :'userExpiredID', null, 'SAVE10', :'discountCodeSaveID', null),
    (1000, 'external', 'USD', 0, :'eventID', :'ticketTypeGeneralID', 'pending', 'General', :'userExpiredHoldID', null, null, null, current_timestamp - interval '1 hour'),
    (900, 'external', 'USD', 100, :'eventID', :'ticketTypeGeneralID', 'pending', 'General', :'userLiveHoldID', null, 'SAVE10', :'discountCodeSaveID', current_timestamp + interval '1 hour'),
    (1000, 'external', 'USD', 0, :'eventID', :'ticketTypeGeneralID', 'pending', 'General', :'userOfferCheckoutID', :'offerCheckoutID', null, null, current_timestamp + interval '1 hour'),
    (900, 'external', 'USD', 100, :'eventID', :'ticketTypeGeneralID', 'refund-requested', 'General', :'userRefundRequestedID', null, 'SAVE10', :'discountCodeSaveID', null),
    (900, 'external', 'USD', 100, :'eventID', :'ticketTypeGeneralID', 'refunded', 'General', :'userRefundedID', null, 'SAVE10', :'discountCodeSaveID', null),
    (2000, 'external', 'USD', 0, :'eventID', :'ticketTypeVipID', 'completed', 'VIP', :'userVipCompletedID', null, null, null, null),
    (2000, 'external', 'USD', 0, :'eventID', :'ticketTypeVipID', 'refund-pending', 'VIP', :'userVipRefundPendingID', null, null, null, null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should count discount code redemptions that still hold a seat
select is(
    (select stats_event_tickets(e)::jsonb->'discount_codes' from event e where e.event_id = :'eventID'),
    jsonb_build_array(
        jsonb_build_object(
            'active', true,
            'code', 'SAVE10',
            'event_discount_code_id', :'discountCodeSaveID',
            'redemptions', 2,
            'title', 'Save ten',

            'available', 8,
            'total_available', 10
        ),
        jsonb_build_object(
            'active', false,
            'code', 'UNUSED',
            'event_discount_code_id', :'discountCodeUnusedID',
            'redemptions', 0,
            'title', 'Unused',

            'available', null,
            'total_available', null
        )
    ),
    'Should count discount code redemptions that still hold a seat'
);

-- Should count sold and allocated seats per ticket type with a floored remainder
select is(
    (select stats_event_tickets(e)::jsonb->'ticket_types' from event e where e.event_id = :'eventID'),
    jsonb_build_array(
        jsonb_build_object(
            'active', true,
            'allocated', 5,
            'event_ticket_type_id', :'ticketTypeGeneralID',
            'order', 1,
            'remaining', 5,
            'seats_total', 10,
            'sold', 2,
            'title', 'General'
        ),
        jsonb_build_object(
            'active', true,
            'allocated', 2,
            'event_ticket_type_id', :'ticketTypeVipID',
            'order', 2,
            'remaining', 0,
            'seats_total', 1,
            'sold', 2,
            'title', 'VIP'
        ),
        jsonb_build_object(
            'active', false,
            'allocated', 0,
            'event_ticket_type_id', :'ticketTypeCompID',
            'order', 3,
            'remaining', 0,
            'seats_total', 0,
            'sold', 0,
            'title', 'Comp'
        )
    ),
    'Should count sold and allocated seats per ticket type with a floored remainder'
);

-- Should expose no money fields for discount codes
select is(
    (
        select array_agg(key order by key)
        from event e
        cross join lateral jsonb_object_keys(stats_event_tickets(e)::jsonb->'discount_codes'->0) as key
        where e.event_id = :'eventID'
    ),
    array['active', 'available', 'code', 'event_discount_code_id', 'redemptions', 'title', 'total_available'],
    'Should expose no money fields for discount codes'
);

-- Should expose no money fields for ticket types
select is(
    (
        select array_agg(key order by key)
        from event e
        cross join lateral jsonb_object_keys(stats_event_tickets(e)::jsonb->'ticket_types'->0) as key
        where e.event_id = :'eventID'
    ),
    array['active', 'allocated', 'event_ticket_type_id', 'order', 'remaining', 'seats_total', 'sold', 'title'],
    'Should expose no money fields for ticket types'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
