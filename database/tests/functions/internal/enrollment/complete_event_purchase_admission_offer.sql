-- Tests completing event purchase admission offers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set checkoutOfferID 'f3080000-0000-0000-0000-000000000001'
\set checkoutUserID 'f3080000-0000-0000-0000-000000000002'
\set communityID 'f3080000-0000-0000-0000-000000000003'
\set eventCategoryID 'f3080000-0000-0000-0000-000000000004'
\set eventID 'f3080000-0000-0000-0000-000000000005'
\set groupCategoryID 'f3080000-0000-0000-0000-000000000006'
\set groupID 'f3080000-0000-0000-0000-000000000007'
\set missingOfferID 'f3080000-0000-0000-0000-000000000008'
\set pendingOfferID 'f3080000-0000-0000-0000-000000000009'
\set pendingUserID 'f3080000-0000-0000-0000-00000000000a'
\set ticketTypeID 'f3080000-0000-0000-0000-00000000000b'

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
select fx_user(:'checkoutUserID');
select fx_user(:'pendingUserID');

-- Admission offers in checkout-pending and pending states
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
    :'checkoutOfferID',
    current_timestamp - interval '1 hour',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'approval',
    'checkout_pending',
    :'checkoutUserID',

    0,
    null,
    0,
    'Checkout admission'
), (
    :'pendingOfferID',
    current_timestamp - interval '1 hour',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'approval',
    'pending',
    :'pendingUserID',

    null,
    null,
    null,
    null
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should complete checkout-pending offers
select is(
    complete_event_purchase_admission_offer(:'checkoutOfferID'),
    true,
    'Should complete checkout-pending offers'
);

-- Should persist completed offer status
select is(
    (select status from admission_offer where admission_offer_id = :'checkoutOfferID'),
    'completed',
    'Should persist completed offer status'
);

-- Should leave pending offers unchanged
select is(
    complete_event_purchase_admission_offer(:'pendingOfferID'),
    false,
    'Should leave pending offers unchanged'
);

-- Should preserve pending offer status
select is(
    (select status from admission_offer where admission_offer_id = :'pendingOfferID'),
    'pending',
    'Should preserve pending offer status'
);

-- Should return false for missing offers
select is(
    complete_event_purchase_admission_offer(:'missingOfferID'),
    false,
    'Should return false for missing offers'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
