-- Tests locking a purchase with its group and event before local completion.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e7b10000-0000-0000-0000-000000000001'
\set eventCategoryID 'e7b10000-0000-0000-0000-000000000002'
\set eventID 'e7b10000-0000-0000-0000-000000000003'
\set eventLapsedHoldID 'e7b10000-0000-0000-0000-000000000004'
\set eventLapsedHoldTicketTypeID 'e7b10000-0000-0000-0000-000000000005'
\set eventReconcileID 'e7b10000-0000-0000-0000-000000000006'
\set eventReconcileTicketTypeID 'e7b10000-0000-0000-0000-000000000007'
\set eventTicketTypeID 'e7b10000-0000-0000-0000-000000000008'
\set expiredPurchaseID 'e7b10000-0000-0000-0000-000000000009'
\set expiredUserID 'e7b10000-0000-0000-0000-000000000010'
\set groupCategoryID 'e7b10000-0000-0000-0000-000000000011'
\set groupID 'e7b10000-0000-0000-0000-000000000012'
\set lapsedHoldPurchaseID 'e7b10000-0000-0000-0000-000000000013'
\set lapsedHoldUserID 'e7b10000-0000-0000-0000-000000000014'
\set lapsedOfferID 'e7b10000-0000-0000-0000-000000000015'
\set lapsedOfferUserID 'e7b10000-0000-0000-0000-000000000016'
\set offerID 'e7b10000-0000-0000-0000-000000000017'
\set offerPurchaseID 'e7b10000-0000-0000-0000-000000000018'
\set offerUserID 'e7b10000-0000-0000-0000-000000000019'
\set otherGroupID 'e7b10000-0000-0000-0000-000000000020'
\set purchaseID 'e7b10000-0000-0000-0000-000000000021'
\set reconcilePurchaseID 'e7b10000-0000-0000-0000-000000000022'
\set reconcileUserID 'e7b10000-0000-0000-0000-000000000023'
\set unknownPurchaseID 'e7b10000-0000-0000-0000-000000000024'
\set userID 'e7b10000-0000-0000-0000-000000000025'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns the groups
select fx_community(:'communityID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Buyer of the expired purchase
select fx_user(:'expiredUserID');

-- Buyer of the pending purchase whose hold lapsed
select fx_user(:'lapsedHoldUserID');

-- Holder of the due offer swept by reconciliation
select fx_user(:'lapsedOfferUserID');

-- Buyer of the offer-linked purchase
select fx_user(:'offerUserID');

-- Buyer of the purchase on the reconciled event
select fx_user(:'reconcileUserID');

-- Buyer of the pending purchase without an offer
select fx_user(:'userID');

-- Group that owns the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group that does not own the events
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Event whose purchases are locked
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event of the pending purchase whose hold lapsed
select fx_event(:'eventLapsedHoldID', :'groupID', :'eventCategoryID');

-- Event whose due offer is swept by reconciliation
select fx_event(:'eventReconcileID', :'groupID', :'eventCategoryID');

-- Ticket type snapshotted by the locked purchases
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID');

-- Ticket type of the event whose pending purchase hold lapsed
select fx_event_ticket_type(:'eventLapsedHoldTicketTypeID', :'eventLapsedHoldID');

-- Ticket type of the reconciled event
select fx_event_ticket_type(:'eventReconcileTicketTypeID', :'eventReconcileID');

-- Due offer that reconciliation expires
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'lapsedOfferID',
    current_timestamp - interval '2 hours',
    :'eventReconcileID',
    :'eventReconcileTicketTypeID',
    current_timestamp - interval '1 hour',
    'waitlist',
    'pending',
    :'lapsedOfferUserID'
);

-- Checkout-pending offer claimed by the offer-linked purchase
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id,

    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    ticket_title
) values (
    :'offerID',
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'checkout_pending',
    :'offerUserID',

    0,
    null,
    0,
    null,
    null,
    'General admission'
);

-- Expired purchase whose hold lapsed
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'expiredPurchaseID',
    0,
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp - interval '10 minutes',
    'expired',
    'General admission',
    :'expiredUserID'
);

-- Pending purchase whose hold lapsed
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'lapsedHoldPurchaseID',
    0,
    :'eventLapsedHoldID',
    :'eventLapsedHoldTicketTypeID',
    current_timestamp - interval '10 minutes',
    'pending',
    'General admission',
    :'lapsedHoldUserID'
);

-- Pending purchase that claims the checkout-pending offer
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id,

    admission_offer_id
) values (
    :'offerPurchaseID',
    0,
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'offerUserID',

    :'offerID'
);

-- Pending purchase without an offer
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'purchaseID',
    0,
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'userID'
);

-- Pending purchase on the event whose due offer is swept
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'reconcilePurchaseID',
    0,
    :'eventReconcileID',
    :'eventReconcileTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'reconcileUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should derive the group from the purchase event when none is given
select results_eq(
    format(
        $$
            select (l.group_row).group_id
            from lock_event_purchase_for_completion(%L::uuid, null) l
        $$,
        :'purchaseID'
    ),
    format($$ values (%L::uuid) $$, :'groupID'),
    'Should derive the group from the purchase event when none is given'
);

-- Should reconcile the event enrollment before locking the purchase
select results_eq(
    format(
        $$
            select (l.purchase_row).event_purchase_id
            from lock_event_purchase_for_completion(%L::uuid, %L::uuid) l
        $$,
        :'reconcilePurchaseID',
        :'groupID'
    ),
    format($$ values (%L::uuid) $$, :'reconcilePurchaseID'),
    'Should reconcile the event enrollment before locking the purchase'
);

select is(
    (
        select status
        from admission_offer
        where admission_offer_id = :'lapsedOfferID'::uuid
    ),
    'expired',
    'Should reconcile the event enrollment before locking the purchase'
);

-- Should reject expired purchases
select throws_ok(
    format(
        $$select * from lock_event_purchase_for_completion(%L::uuid, %L::uuid)$$,
        :'expiredPurchaseID',
        :'groupID'
    ),
    'OCG01',
    'purchase hold has expired',
    'Should reject expired purchases'
);

-- Should reject pending purchases whose hold lapsed
select throws_ok(
    format(
        $$select * from lock_event_purchase_for_completion(%L::uuid, %L::uuid)$$,
        :'lapsedHoldPurchaseID',
        :'groupID'
    ),
    'OCG01',
    'purchase hold has expired',
    'Should reject pending purchases whose hold lapsed'
);

-- Should reject purchases that belong to another group
select throws_ok(
    format(
        $$select * from lock_event_purchase_for_completion(%L::uuid, %L::uuid)$$,
        :'purchaseID',
        :'otherGroupID'
    ),
    'OCG01',
    'purchase not found',
    'Should reject purchases that belong to another group'
);

-- Should reject unknown purchases
select throws_ok(
    format(
        $$select * from lock_event_purchase_for_completion(%L::uuid, null)$$,
        :'unknownPurchaseID'
    ),
    'OCG01',
    'purchase not found',
    'Should reject unknown purchases'
);

-- Should return the locked rows with the claimed admission offer
select results_eq(
    format(
        $$
            select
                (l.admission_offer_row).admission_offer_id,
                (l.event_row).event_id,
                (l.group_row).group_id,
                (l.purchase_row).event_purchase_id
            from lock_event_purchase_for_completion(%L::uuid, %L::uuid) l
        $$,
        :'offerPurchaseID',
        :'groupID'
    ),
    format(
        $$ values (%L::uuid, %L::uuid, %L::uuid, %L::uuid) $$,
        :'offerID',
        :'eventID',
        :'groupID',
        :'offerPurchaseID'
    ),
    'Should return the locked rows with the claimed admission offer'
);

-- Should return the locked rows without an admission offer
select results_eq(
    format(
        $$
            select
                (l.admission_offer_row).admission_offer_id,
                (l.event_row).event_id,
                (l.group_row).group_id,
                (l.purchase_row).event_purchase_id
            from lock_event_purchase_for_completion(%L::uuid, %L::uuid) l
        $$,
        :'purchaseID',
        :'groupID'
    ),
    format(
        $$ values (null::uuid, %L::uuid, %L::uuid, %L::uuid) $$,
        :'eventID',
        :'groupID',
        :'purchaseID'
    ),
    'Should return the locked rows without an admission offer'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
