-- Tests the claimable admission offer predicate.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ac1a0000-0000-0000-0000-000000000001'
\set completedOfferID 'ac1a0000-0000-0000-0000-000000000002'
\set completedPurchaseID 'ac1a0000-0000-0000-0000-000000000003'
\set completedUserID 'ac1a0000-0000-0000-0000-000000000004'
\set eventCategoryID 'ac1a0000-0000-0000-0000-000000000005'
\set eventID 'ac1a0000-0000-0000-0000-000000000006'
\set groupCategoryID 'ac1a0000-0000-0000-0000-000000000007'
\set groupID 'ac1a0000-0000-0000-0000-000000000008'
\set lapsedOfferID 'ac1a0000-0000-0000-0000-000000000009'
\set lapsedUserID 'ac1a0000-0000-0000-0000-000000000010'
\set liveOfferID 'ac1a0000-0000-0000-0000-000000000011'
\set liveUserID 'ac1a0000-0000-0000-0000-000000000012'
\set refundPendingOfferID 'ac1a0000-0000-0000-0000-000000000013'
\set refundPendingPurchaseID 'ac1a0000-0000-0000-0000-000000000014'
\set refundPendingUserID 'ac1a0000-0000-0000-0000-000000000015'
\set refundRecoveryOfferID 'ac1a0000-0000-0000-0000-000000000016'
\set refundRecoveryPurchaseID 'ac1a0000-0000-0000-0000-000000000017'
\set refundRecoveryUserID 'ac1a0000-0000-0000-0000-000000000018'
\set refundRequestedOfferID 'ac1a0000-0000-0000-0000-000000000019'
\set refundRequestedPurchaseID 'ac1a0000-0000-0000-0000-000000000020'
\set refundRequestedUserID 'ac1a0000-0000-0000-0000-000000000021'
\set ticketTypeID 'ac1a0000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the offer event
select fx_community(:'communityID');

-- Offer owners, one per scenario
select fx_user(:'completedUserID');
select fx_user(:'lapsedUserID');
select fx_user(:'liveUserID');
select fx_user(:'refundPendingUserID');
select fx_user(:'refundRecoveryUserID');
select fx_user(:'refundRequestedUserID');

-- Event category of the offer event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category of the offer group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the offer event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose offers are evaluated
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Ticket tier reserved by every offer
select fx_event_ticket_type(:'ticketTypeID', :'eventID');

-- Offers: live, lapsed, and live behind completed or refunding purchases
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    created_at,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values
    (:'completedOfferID', 0, current_timestamp - interval '1 hour', 0, :'eventID', :'ticketTypeID', current_timestamp + interval '1 day', 'approval', 'checkout_pending', 'General admission', :'completedUserID'),
    (:'lapsedOfferID', 0, current_timestamp - interval '2 days', 0, :'eventID', :'ticketTypeID', current_timestamp - interval '1 day', 'approval', 'pending', 'General admission', :'lapsedUserID'),
    (:'liveOfferID', 0, current_timestamp - interval '1 hour', 0, :'eventID', :'ticketTypeID', current_timestamp + interval '1 day', 'approval', 'pending', 'General admission', :'liveUserID'),
    (:'refundPendingOfferID', 0, current_timestamp - interval '1 hour', 0, :'eventID', :'ticketTypeID', current_timestamp + interval '1 day', 'approval', 'checkout_pending', 'General admission', :'refundPendingUserID'),
    (:'refundRecoveryOfferID', 0, current_timestamp - interval '1 hour', 0, :'eventID', :'ticketTypeID', current_timestamp + interval '1 day', 'approval', 'checkout_pending', 'General admission', :'refundRecoveryUserID'),
    (:'refundRequestedOfferID', 0, current_timestamp - interval '1 hour', 0, :'eventID', :'ticketTypeID', current_timestamp + interval '1 day', 'approval', 'checkout_pending', 'General admission', :'refundRequestedUserID');

-- Purchases linked to the live offers: completed and each refunding status
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values
    (:'completedOfferID', 0, 'USD', :'eventID', :'completedPurchaseID', :'ticketTypeID', 'completed', 'General admission', :'completedUserID'),
    (:'refundPendingOfferID', 0, 'USD', :'eventID', :'refundPendingPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'refundPendingUserID'),
    (:'refundRecoveryOfferID', 0, 'USD', :'eventID', :'refundRecoveryPurchaseID', :'ticketTypeID', 'refund-recovery-pending', 'General admission', :'refundRecoveryUserID'),
    (:'refundRequestedOfferID', 0, 'USD', :'eventID', :'refundRequestedPurchaseID', :'ticketTypeID', 'refund-requested', 'General admission', :'refundRequestedUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should not treat lapsed offers as claimable
select is(
    admission_offer_is_claimable(ao),
    false,
    'Should not treat lapsed offers as claimable'
)
from admission_offer ao
where ao.admission_offer_id = :'lapsedOfferID';

-- Should not treat live offers behind a refunding purchase as claimable
select is(
    array_agg(admission_offer_is_claimable(ao) order by ao.admission_offer_id),
    array[false, false, false],
    'Should not treat live offers behind a refunding purchase as claimable'
)
from admission_offer ao
where ao.admission_offer_id in (
    :'refundPendingOfferID',
    :'refundRecoveryOfferID',
    :'refundRequestedOfferID'
);

-- Should treat live offers as claimable
select is(
    admission_offer_is_claimable(ao),
    true,
    'Should treat live offers as claimable'
)
from admission_offer ao
where ao.admission_offer_id = :'liveOfferID';

-- Should treat live offers with a completed purchase as claimable
select is(
    admission_offer_is_claimable(ao),
    true,
    'Should treat live offers with a completed purchase as claimable'
)
from admission_offer ao
where ao.admission_offer_id = :'completedOfferID';

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
