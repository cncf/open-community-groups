-- Tests counting the enforced redemptions of an event discount code.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'edc50000-0000-0000-0000-000000000001'
\set countedDiscountCodeID 'edc50000-0000-0000-0000-000000000002'
\set eventCategoryID 'edc50000-0000-0000-0000-000000000003'
\set eventID 'edc50000-0000-0000-0000-000000000004'
\set groupCategoryID 'edc50000-0000-0000-0000-000000000005'
\set groupID 'edc50000-0000-0000-0000-000000000006'
\set releasedDiscountCodeID 'edc50000-0000-0000-0000-000000000007'
\set ticketTypeID 'edc50000-0000-0000-0000-000000000008'
\set unusedDiscountCodeID 'edc50000-0000-0000-0000-000000000009'
\set userCompletedID 'edc50000-0000-0000-0000-000000000010'
\set userExpiredHoldID 'edc50000-0000-0000-0000-000000000011'
\set userExpiredID 'edc50000-0000-0000-0000-000000000012'
\set userLivePendingID 'edc50000-0000-0000-0000-000000000013'
\set userRefundedID 'edc50000-0000-0000-0000-000000000014'
\set userRefundPendingID 'edc50000-0000-0000-0000-000000000015'
\set userRefundRecoveryID 'edc50000-0000-0000-0000-000000000016'
\set userRefundRequestedID 'edc50000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userCompletedID');
select fx_user(:'userExpiredHoldID');
select fx_user(:'userExpiredID');
select fx_user(:'userLivePendingID');
select fx_user(:'userRefundedID');
select fx_user(:'userRefundPendingID');
select fx_user(:'userRefundRecoveryID');
select fx_user(:'userRefundRequestedID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Ticketed event whose purchases redeem the discount codes
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));

-- Discount codes with counted, released and no redemptions
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    code,
    event_id,
    kind,
    title,
    total_available
) values
    (:'countedDiscountCodeID', 500, 'COUNTED', :'eventID', 'fixed_amount', 'Counted discount', 10),
    (:'releasedDiscountCodeID', 500, 'RELEASED', :'eventID', 'fixed_amount', 'Released discount', 10),
    (:'unusedDiscountCodeID', 500, 'UNUSED', :'eventID', 'fixed_amount', 'Unused discount', 10);

-- Ticket type sold with the discount codes
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 20,
    'title', 'General admission'
));

-- Settled sales and a live checkout hold that redeem the counted code
insert into event_purchase (
    amount_minor,
    currency_code,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values
    (0, 'USD', 'COUNTED', :'countedDiscountCodeID', :'eventID', :'ticketTypeID', null, 'completed', 'General admission', :'userCompletedID'),
    (0, 'USD', 'COUNTED', :'countedDiscountCodeID', :'eventID', :'ticketTypeID', current_timestamp + interval '10 minutes', 'pending', 'General admission', :'userLivePendingID'),
    (0, 'USD', 'COUNTED', :'countedDiscountCodeID', :'eventID', :'ticketTypeID', null, 'refund-requested', 'General admission', :'userRefundRequestedID');

-- Expired holds and refunding or refunded purchases that released the released code
insert into event_purchase (
    amount_minor,
    currency_code,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values
    (0, 'USD', 'RELEASED', :'releasedDiscountCodeID', :'eventID', :'ticketTypeID', null, 'expired', 'General admission', :'userExpiredID'),
    (0, 'USD', 'RELEASED', :'releasedDiscountCodeID', :'eventID', :'ticketTypeID', current_timestamp - interval '10 minutes', 'pending', 'General admission', :'userExpiredHoldID'),
    (0, 'USD', 'RELEASED', :'releasedDiscountCodeID', :'eventID', :'ticketTypeID', null, 'refund-pending', 'General admission', :'userRefundPendingID'),
    (0, 'USD', 'RELEASED', :'releasedDiscountCodeID', :'eventID', :'ticketTypeID', null, 'refund-recovery-pending', 'General admission', :'userRefundRecoveryID'),
    (0, 'USD', 'RELEASED', :'releasedDiscountCodeID', :'eventID', :'ticketTypeID', null, 'refunded', 'General admission', :'userRefundedID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should count completed, refund-requested and live pending purchases of the code
select is(
    event_discount_code_redemption_count(:'countedDiscountCodeID'::uuid),
    3,
    'Should count completed, refund-requested and live pending purchases of the code'
);

-- Should ignore expired holds and refund-pending, refund-recovery-pending, refunded and expired purchases
select is(
    event_discount_code_redemption_count(:'releasedDiscountCodeID'::uuid),
    0,
    'Should ignore expired holds and refund-pending, refund-recovery-pending, refunded and expired purchases'
);

-- Should ignore purchases redeeming other discount codes
select is(
    event_discount_code_redemption_count(:'unusedDiscountCodeID'::uuid),
    0,
    'Should ignore purchases redeeming other discount codes'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
