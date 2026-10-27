-- Tests expiring a single event checkout hold.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79210000-0000-0000-0000-000000000001'
\set completedPurchaseID '79210000-0000-0000-0000-000000000011'
\set completedUserID '79210000-0000-0000-0000-000000000012'
\set discountCodeID '79210000-0000-0000-0000-000000000002'
\set eventCategoryID '79210000-0000-0000-0000-000000000003'
\set eventID '79210000-0000-0000-0000-000000000004'
\set expiredPurchaseID '79210000-0000-0000-0000-000000000013'
\set expiredUserID '79210000-0000-0000-0000-000000000014'
\set groupCategoryID '79210000-0000-0000-0000-000000000006'
\set groupID '79210000-0000-0000-0000-000000000007'
\set lapsedPurchaseID '79210000-0000-0000-0000-000000000015'
\set lapsedUserID '79210000-0000-0000-0000-000000000016'
\set missingPurchaseID '79210000-0000-0000-0000-000000000017'
\set purchaseID '79210000-0000-0000-0000-000000000009'
\set ticketTypeID '79210000-0000-0000-0000-000000000005'
\set untouchedDiscountCodeID '79210000-0000-0000-0000-000000000018'
\set userID '79210000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the checkout event
select fx_community(:'communityID');

-- User whose completed purchase is never expired
select fx_user(:'completedUserID');

-- User whose purchase is already expired
select fx_user(:'expiredUserID');

-- User whose pending hold already passed its deadline
select fx_user(:'lapsedUserID');

-- User whose future pending hold is expired
select fx_user(:'userID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

-- Pending attendee row with registration answers created during checkout
insert into event_attendee (event_id, manually_invited, status, user_id)
values (
    :'eventID',
    false,
    'registration-questions-pending',
    :'userID'
);

-- Discount code reserved by the future pending hold
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    true,
    500,
    0,
    true,
    'SAVE5',
    :'eventID',
    'fixed_amount',
    'Save 5'
);

-- Discount code that no expired hold references
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'untouchedDiscountCodeID',
    true,
    500,
    0,
    true,
    'UNTOUCHED5',
    :'eventID',
    'fixed_amount',
    'Untouched 5'
);

-- Ticket type
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Future discounted pending purchase
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'purchaseID',
    0,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'ticketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'userID'
);

-- Completed purchase, expired purchase and lapsed pending hold without discounts
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values
    (
        :'completedPurchaseID',
        0,
        'USD',
        0,
        :'eventID',
        :'ticketTypeID',
        null,
        'completed',
        'General admission',
        :'completedUserID'
    ),
    (
        :'expiredPurchaseID',
        0,
        'USD',
        0,
        :'eventID',
        :'ticketTypeID',
        now() - interval '1 day',
        'expired',
        'General admission',
        :'expiredUserID'
    ),
    (
        :'lapsedPurchaseID',
        0,
        'USD',
        0,
        :'eventID',
        :'ticketTypeID',
        now() - interval '2 hours',
        'pending',
        'General admission',
        :'lapsedUserID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report expiring a future pending hold
select is(
    expire_event_checkout_hold(:'purchaseID'),
    true,
    'Should report expiring a future pending hold'
);

-- Should expire a future pending hold, capping its deadline to now
select results_eq(
    format(
        $$
            select status, hold_expires_at
            from event_purchase
            where event_purchase_id = %L::uuid
        $$,
        :'purchaseID'
    ),
    $$ values ('expired'::text, current_timestamp) $$,
    'Should expire a future pending hold, capping its deadline to now'
);

-- Should delete the registration-questions-pending checkout attendee row
select is(
    (
        select count(*)::int
        from event_attendee
        where event_id = :'eventID'
        and user_id = :'userID'
    ),
    0,
    'Should delete the registration-questions-pending checkout attendee row'
);

-- Should restore discount availability when the hold reserved a discount
select is(
    (
        select available
        from event_discount_code
        where event_discount_code_id = :'discountCodeID'
    ),
    1,
    'Should restore discount availability when the hold reserved a discount'
);

-- Should report expiring an already-lapsed pending hold
select is(
    expire_event_checkout_hold(:'lapsedPurchaseID'),
    true,
    'Should report expiring an already-lapsed pending hold'
);

-- Should keep the deadline of an already-lapsed pending hold
select results_eq(
    format(
        $$
            select status, hold_expires_at
            from event_purchase
            where event_purchase_id = %L::uuid
        $$,
        :'lapsedPurchaseID'
    ),
    $$ values ('expired'::text, current_timestamp - interval '2 hours') $$,
    'Should keep the deadline of an already-lapsed pending hold'
);

-- Should leave discount codes untouched when the hold has none
select is(
    (
        select available
        from event_discount_code
        where event_discount_code_id = :'untouchedDiscountCodeID'
    ),
    0,
    'Should leave discount codes untouched when the hold has none'
);

-- Should return false for completed and expired purchases
select results_eq(
    format(
        $$
            select expire_event_checkout_hold(purchase_id)
            from unnest(array[%L::uuid, %L::uuid]) with ordinality as p(purchase_id, position)
            order by position
        $$,
        :'completedPurchaseID',
        :'expiredPurchaseID'
    ),
    $$ values (false), (false) $$,
    'Should return false for completed and expired purchases'
);

-- Should leave completed and expired purchases unchanged
select results_eq(
    format(
        $$
            select status, hold_expires_at
            from event_purchase
            where event_purchase_id in (%L::uuid, %L::uuid)
            order by event_purchase_id
        $$,
        :'completedPurchaseID',
        :'expiredPurchaseID'
    ),
    $$ values
        ('completed'::text, null::timestamptz),
        ('expired'::text, current_timestamp - interval '1 day')
    $$,
    'Should leave completed and expired purchases unchanged'
);

-- Should return false for an unknown purchase
select is(
    expire_event_checkout_hold(:'missingPurchaseID'),
    false,
    'Should return false for an unknown purchase'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
