-- Tests detecting paid-capable event ticket configuration.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c140000-0000-0000-0000-000000000001'
\set eventCategoryID '0c140000-0000-0000-0000-000000000002'
\set eventFreeID '0c140000-0000-0000-0000-000000000003'
\set eventNoTicketsID '0c140000-0000-0000-0000-000000000004'
\set eventPaidID '0c140000-0000-0000-0000-000000000005'
\set freeTicketTypeID '0c140000-0000-0000-0000-000000000006'
\set freeWindowID '0c140000-0000-0000-0000-000000000007'
\set groupCategoryID '0c140000-0000-0000-0000-000000000008'
\set groupID '0c140000-0000-0000-0000-000000000009'
\set paidTicketTypeID '0c140000-0000-0000-0000-00000000000a'
\set paidWindowID '0c140000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events without tickets, with free tickets, and with paid tickets
select fx_event(:'eventFreeID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));
select fx_event(:'eventNoTicketsID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventPaidID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));

-- Free and inactive paid ticket types
select fx_event_ticket_type(:'freeTicketTypeID', :'eventFreeID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'paidTicketTypeID', :'eventPaidID', jsonb_build_object(
    'active', false,
    'seats_total', 10
));

-- Zero and future positive price windows
select fx_event_ticket_price_window(:'freeWindowID', :'freeTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'paidWindowID', :'paidTicketTypeID', jsonb_build_object(
    'amount_minor', 2500,
    'starts_at', current_timestamp + interval '30 days'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should detect positive prices on inactive tiers and future windows
select is(
    is_event_paid_capable(:'eventPaidID'::uuid),
    true,
    'Should detect positive prices on inactive tiers and future windows'
);

-- Should return false when every configured price is zero
select is(
    is_event_paid_capable(:'eventFreeID'::uuid),
    false,
    'Should return false when every configured price is zero'
);

-- Should return false when the event has no ticket types
select is(
    is_event_paid_capable(:'eventNoTicketsID'::uuid),
    false,
    'Should return false when the event has no ticket types'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
