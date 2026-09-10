-- Tests reconciling event admission offers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set abandonedOfferID 'f3060000-0000-0000-0000-000000000001'
\set abandonedUserID 'f3060000-0000-0000-0000-000000000002'
\set checkoutExpiredOfferID 'f3060000-0000-0000-0000-000000000003'
\set checkoutExpiredUserID 'f3060000-0000-0000-0000-000000000004'
\set communityID 'f3060000-0000-0000-0000-000000000005'
\set completedOfferID 'f3060000-0000-0000-0000-000000000006'
\set completedPurchaseID 'f3060000-0000-0000-0000-000000000007'
\set completedUserID 'f3060000-0000-0000-0000-000000000008'
\set eventCategoryID 'f3060000-0000-0000-0000-000000000009'
\set eventID 'f3060000-0000-0000-0000-00000000000a'
\set groupCategoryID 'f3060000-0000-0000-0000-00000000000b'
\set groupID 'f3060000-0000-0000-0000-00000000000c'
\set otherEventID 'f3060000-0000-0000-0000-00000000000d'
\set otherOfferID 'f3060000-0000-0000-0000-00000000000e'
\set otherTicketTypeID 'f3060000-0000-0000-0000-00000000000f'
\set otherUserID 'f3060000-0000-0000-0000-000000000010'
\set pendingExpiredOfferID 'f3060000-0000-0000-0000-000000000011'
\set pendingExpiredUserID 'f3060000-0000-0000-0000-000000000012'
\set pendingLiveOfferID 'f3060000-0000-0000-0000-000000000013'
\set pendingLiveUserID 'f3060000-0000-0000-0000-000000000014'
\set purchaseOfferID 'f3060000-0000-0000-0000-000000000015'
\set purchasePurchaseID 'f3060000-0000-0000-0000-000000000016'
\set purchaseUserID 'f3060000-0000-0000-0000-000000000017'
\set ticketTypeID 'f3060000-0000-0000-0000-000000000018'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group, events, ticket types and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');
select fx_event_ticket_type(:'ticketTypeID', :'eventID');
select fx_event_ticket_type(:'otherTicketTypeID', :'otherEventID');
select fx_user(:'abandonedUserID');
select fx_user(:'checkoutExpiredUserID');
select fx_user(:'completedUserID');
select fx_user(:'otherUserID');
select fx_user(:'pendingExpiredUserID');
select fx_user(:'pendingLiveUserID');
select fx_user(:'purchaseUserID');

-- Admission offers covering due, live and checkout-pending reconciliation states
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
) values (
    :'abandonedOfferID',
    current_timestamp - interval '1 hour',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'approval',
    'checkout_pending',
    :'abandonedUserID',

    0,
    null,
    0,
    'Abandoned admission'
), (
    :'checkoutExpiredOfferID',
    current_timestamp - interval '2 hours',
    :'eventID',
    :'ticketTypeID',
    current_timestamp - interval '1 hour',
    'approval',
    'checkout_pending',
    :'checkoutExpiredUserID',

    0,
    null,
    0,
    'Expired checkout admission'
), (
    :'completedOfferID',
    current_timestamp - interval '1 hour',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'approval',
    'checkout_pending',
    :'completedUserID',

    0,
    null,
    0,
    'Completed admission'
), (
    :'otherOfferID',
    current_timestamp - interval '2 hours',
    :'otherEventID',
    :'otherTicketTypeID',
    current_timestamp - interval '1 hour',
    'waitlist',
    'pending',
    :'otherUserID',

    null,
    null,
    null,
    null
), (
    :'pendingExpiredOfferID',
    current_timestamp - interval '2 hours',
    :'eventID',
    :'ticketTypeID',
    current_timestamp - interval '1 hour',
    'waitlist',
    'pending',
    :'pendingExpiredUserID',

    null,
    null,
    null,
    null
), (
    :'pendingLiveOfferID',
    current_timestamp - interval '1 hour',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'waitlist',
    'pending',
    :'pendingLiveUserID',

    null,
    null,
    null,
    null
), (
    :'purchaseOfferID',
    current_timestamp - interval '1 hour',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'approval',
    'checkout_pending',
    :'purchaseUserID',

    0,
    null,
    0,
    'Held admission'
);

-- Purchases that keep checkout-pending offers reserved
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'completedOfferID',
    0,
    'USD',
    :'eventID',
    :'completedPurchaseID',
    :'ticketTypeID',
    null,
    'completed',
    'Completed admission',
    :'completedUserID'
), (
    :'purchaseOfferID',
    0,
    'USD',
    :'eventID',
    :'purchasePurchaseID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'pending',
    'Held admission',
    :'purchaseUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reconcile due and abandoned admission offers
select lives_ok(
    format(
        $$select reconcile_event_admission_offers((select e from event e where e.event_id = %L::uuid), (select g from "group" g where g.group_id = %L::uuid))$$,
        :'eventID',
        :'groupID'
    ),
    'Should reconcile due and abandoned admission offers'
);

-- Should expire checkout-pending offers after their deadline
select is(
    (select status from admission_offer where admission_offer_id = :'checkoutExpiredOfferID'),
    'expired',
    'Should expire checkout-pending offers after their deadline'
);

-- Should expire pending offers and audit the expiry
select results_eq(
    format(
        $$
            select
                ao.status,
                exists (
                    select 1
                    from audit_log al
                    where al.action = 'admission_offer_expired'
                    and al.event_id = %L::uuid
                    and al.resource_id = %L::uuid
                    and al.resource_type = 'admission_offer'
                )
            from admission_offer ao
            where ao.admission_offer_id = %L::uuid
        $$,
        :'eventID',
        :'pendingExpiredOfferID',
        :'pendingExpiredOfferID'
    ),
    $$ values ('expired'::text, true) $$,
    'Should expire pending offers and audit the expiry'
);

-- Should keep checkout-pending offers with completed purchases
select is(
    (select status from admission_offer where admission_offer_id = :'completedOfferID'),
    'checkout_pending',
    'Should keep checkout-pending offers with completed purchases'
);

-- Should keep checkout-pending offers with unexpired pending purchases
select is(
    (select status from admission_offer where admission_offer_id = :'purchaseOfferID'),
    'checkout_pending',
    'Should keep checkout-pending offers with unexpired pending purchases'
);

-- Should keep pending offers before their deadline
select is(
    (select status from admission_offer where admission_offer_id = :'pendingLiveOfferID'),
    'pending',
    'Should keep pending offers before their deadline'
);

-- Should leave other events untouched
select is(
    (select status from admission_offer where admission_offer_id = :'otherOfferID'),
    'pending',
    'Should leave other events untouched'
);

-- Should return abandoned checkout-pending offers to pending
select is(
    (select status from admission_offer where admission_offer_id = :'abandonedOfferID'),
    'pending',
    'Should return abandoned checkout-pending offers to pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
