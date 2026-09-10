-- Tests detecting purchases that still await refund recovery for a user.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f2070000-0000-0000-0000-000000000001'
\set eventCategoryID 'f2070000-0000-0000-0000-000000000002'
\set eventID 'f2070000-0000-0000-0000-000000000003'
\set groupCategoryID 'f2070000-0000-0000-0000-000000000004'
\set groupID 'f2070000-0000-0000-0000-000000000005'
\set otherUserID 'f2070000-0000-0000-0000-000000000006'
\set recoveryPurchaseID 'f2070000-0000-0000-0000-000000000007'
\set refundedPurchaseID 'f2070000-0000-0000-0000-000000000008'
\set ticketTypeID 'f2070000-0000-0000-0000-000000000009'
\set userID 'f2070000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group, event, ticket type and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_event_ticket_type(:'ticketTypeID', :'eventID');
select fx_user(:'otherUserID');
select fx_user(:'userID');

-- Purchase awaiting refund recovery and an already refunded one
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values
    (0, 'USD', :'eventID', :'recoveryPurchaseID', :'ticketTypeID', 'refund-recovery-pending', 'General admission', :'userID'),
    (0, 'USD', :'eventID', :'refundedPurchaseID', :'ticketTypeID', 'refunded', 'General admission', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should detect a purchase awaiting refund recovery
select ok(
    event_has_pending_refund_recovery(:'eventID', :'userID', null),
    'Should detect a purchase awaiting refund recovery'
);

-- Should ignore the excluded purchase
select is(
    event_has_pending_refund_recovery(:'eventID', :'userID', :'recoveryPurchaseID'),
    false,
    'Should ignore the excluded purchase'
);

-- Should still detect recovery when another purchase is excluded
select ok(
    event_has_pending_refund_recovery(:'eventID', :'userID', :'refundedPurchaseID'),
    'Should still detect recovery when another purchase is excluded'
);

-- Should ignore other users
select is(
    event_has_pending_refund_recovery(:'eventID', :'otherUserID', null),
    false,
    'Should ignore other users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
