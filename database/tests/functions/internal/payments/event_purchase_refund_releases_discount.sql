-- Tests which refund kinds return their discount reservation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep the discount reserved by automatic unfulfillable-checkout refunds
select is(
    event_purchase_refund_releases_discount('automatic-unfulfillable-checkout'),
    false,
    'Should keep the discount reserved by automatic unfulfillable-checkout refunds'
);

-- Should release the discount of attendance cancellation refunds
select is(
    event_purchase_refund_releases_discount('attendance-cancellation'),
    true,
    'Should release the discount of attendance cancellation refunds'
);

-- Should release the discount of event cancellation refunds
select is(
    event_purchase_refund_releases_discount('event-cancellation'),
    true,
    'Should release the discount of event cancellation refunds'
);

-- Should release the discount of refund request approval refunds
select is(
    event_purchase_refund_releases_discount('refund-request-approval'),
    true,
    'Should release the discount of refund request approval refunds'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
