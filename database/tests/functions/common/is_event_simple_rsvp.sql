-- Tests detecting the single-free-public-tier RSVP shape.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c150000-0000-0000-0000-000000000001'
\set eventCategoryID '0c150000-0000-0000-0000-000000000002'
\set eventInactiveID '0c150000-0000-0000-0000-000000000003'
\set eventMultipleID '0c150000-0000-0000-0000-000000000004'
\set eventNoCurrentPriceID '0c150000-0000-0000-0000-000000000005'
\set eventPaidID '0c150000-0000-0000-0000-000000000006'
\set eventPrivateOnlyID '0c150000-0000-0000-0000-000000000007'
\set eventSimpleID '0c150000-0000-0000-0000-000000000008'
\set groupCategoryID '0c150000-0000-0000-0000-000000000009'
\set groupID '0c150000-0000-0000-0000-00000000000a'
\set ticketInactiveActiveID '0c150000-0000-0000-0000-000000000010'
\set ticketInactiveDisabledID '0c150000-0000-0000-0000-000000000011'
\set ticketMultipleFirstID '0c150000-0000-0000-0000-000000000012'
\set ticketMultipleSecondID '0c150000-0000-0000-0000-000000000013'
\set ticketNoCurrentPriceID '0c150000-0000-0000-0000-000000000014'
\set ticketPaidID '0c150000-0000-0000-0000-000000000015'
\set ticketPrivateOnlyID '0c150000-0000-0000-0000-000000000016'
\set ticketSimplePrivateID '0c150000-0000-0000-0000-000000000018'
\set ticketSimplePublicID '0c150000-0000-0000-0000-000000000017'
\set windowInactiveActiveID '0c150000-0000-0000-0000-000000000020'
\set windowInactiveDisabledID '0c150000-0000-0000-0000-000000000021'
\set windowMultipleFirstID '0c150000-0000-0000-0000-000000000022'
\set windowMultipleSecondID '0c150000-0000-0000-0000-000000000023'
\set windowNoCurrentPriceID '0c150000-0000-0000-0000-000000000024'
\set windowPaidID '0c150000-0000-0000-0000-000000000025'
\set windowPrivateOnlyID '0c150000-0000-0000-0000-000000000026'
\set windowSimplePrivateID '0c150000-0000-0000-0000-000000000028'
\set windowSimplePublicID '0c150000-0000-0000-0000-000000000027'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events covering each public ticket shape
select fx_event(:'eventInactiveID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));
select fx_event(:'eventMultipleID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));
select fx_event(:'eventNoCurrentPriceID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));
select fx_event(:'eventPaidID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));
select fx_event(:'eventPrivateOnlyID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));
select fx_event(:'eventSimpleID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));

-- Ticket tiers covering active, inactive, public, and private shapes
select fx_event_ticket_type(:'ticketInactiveActiveID', :'eventInactiveID', jsonb_build_object(
    'seats_total', 10
));
select fx_event_ticket_type(:'ticketInactiveDisabledID', :'eventInactiveID', jsonb_build_object(
    'active', false,
    'order', 2,
    'seats_total', 10
));
select fx_event_ticket_type(:'ticketMultipleFirstID', :'eventMultipleID', jsonb_build_object(
    'seats_total', 10
));
select fx_event_ticket_type(:'ticketMultipleSecondID', :'eventMultipleID', jsonb_build_object(
    'order', 2,
    'seats_total', 10
));
select fx_event_ticket_type(:'ticketNoCurrentPriceID', :'eventNoCurrentPriceID', jsonb_build_object(
    'seats_total', 10
));
select fx_event_ticket_type(:'ticketPaidID', :'eventPaidID', jsonb_build_object(
    'seats_total', 10,
    'title', 'Paid'
));
select fx_event_ticket_type(:'ticketPrivateOnlyID', :'eventPrivateOnlyID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 10
));
select fx_event_ticket_type(:'ticketSimplePublicID', :'eventSimpleID', jsonb_build_object(
    'seats_total', 10
));
select fx_event_ticket_type(:'ticketSimplePrivateID', :'eventSimpleID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 2,
    'seats_total', 10
));

-- Price windows covering current free, current paid, and expired prices
select fx_event_ticket_price_window(:'windowInactiveActiveID', :'ticketInactiveActiveID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'windowInactiveDisabledID', :'ticketInactiveDisabledID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'windowMultipleFirstID', :'ticketMultipleFirstID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'windowMultipleSecondID', :'ticketMultipleSecondID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'windowNoCurrentPriceID', :'ticketNoCurrentPriceID', jsonb_build_object(
    'amount_minor', 0,
    'ends_at', current_timestamp - interval '1 hour'
));
select fx_event_ticket_price_window(:'windowPaidID', :'ticketPaidID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'windowPrivateOnlyID', :'ticketPrivateOnlyID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'windowSimplePublicID', :'ticketSimplePublicID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'windowSimplePrivateID', :'ticketSimplePrivateID', jsonb_build_object('amount_minor', 2500));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore inactive public tiers
select ok(
    is_event_simple_rsvp(:'eventInactiveID'::uuid),
    'Should ignore inactive public tiers'
);

-- Should reject multiple active public tiers
select is(
    is_event_simple_rsvp(:'eventMultipleID'::uuid),
    false,
    'Should reject multiple active public tiers'
);

-- Should reject public tiers without a current price
select is(
    is_event_simple_rsvp(:'eventNoCurrentPriceID'::uuid),
    false,
    'Should reject public tiers without a current price'
);

-- Should reject a paid public tier
select is(
    is_event_simple_rsvp(:'eventPaidID'::uuid),
    false,
    'Should reject a paid public tier'
);

-- Should reject events without an active public tier
select is(
    is_event_simple_rsvp(:'eventPrivateOnlyID'::uuid),
    false,
    'Should reject events without an active public tier'
);

-- Should accept one free public tier alongside private tiers
select ok(
    is_event_simple_rsvp(:'eventSimpleID'::uuid),
    'Should accept one free public tier alongside private tiers'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
