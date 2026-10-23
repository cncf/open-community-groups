-- Tests reporting whether admission offer paid seats can be collected.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f3140000-0000-0000-0000-000000000001'
\set eventCategoryID 'f3140000-0000-0000-0000-000000000002'
\set groupCategoryID 'f3140000-0000-0000-0000-000000000003'
\set readyEventID 'f3140000-0000-0000-0000-000000000004'
\set readyGroupID 'f3140000-0000-0000-0000-000000000005'
\set unnamedSellerEventID 'f3140000-0000-0000-0000-000000000006'
\set unnamedSellerGroupID 'f3140000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and categories
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group with a complete Stripe payment recipient
select fx_group(:'readyGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_offer_ready',
        'seller_display_name', 'Offer Ready Seller'
    )
));

-- Group whose Stripe payment recipient lacks a seller name
select fx_group(:'unnamedSellerGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_offer_unnamed'
    )
));

-- Stripe-complete paid event on the ready group
select fx_event(:'readyEventID', :'readyGroupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'in-person',
    'manual_tax_rate_ids', '{}'::text[],
    'payment_currency_code', 'USD',
    'tax_calculation_mode', 'automatic',
    'venue_address', '1 Ready Way',
    'venue_city', 'Ready City',
    'venue_country_code', 'US',
    'venue_name', 'Ready Hall',
    'venue_zip_code', '12345'
));

-- Stripe-complete paid event on the group without a seller name
select fx_event(:'unnamedSellerEventID', :'unnamedSellerGroupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'in-person',
    'manual_tax_rate_ids', '{}'::text[],
    'payment_currency_code', 'USD',
    'tax_calculation_mode', 'automatic',
    'venue_address', '1 Unnamed Way',
    'venue_city', 'Unnamed City',
    'venue_country_code', 'US',
    'venue_name', 'Unnamed Hall',
    'venue_zip_code', '12345'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report a collectable paid seat as ready
select is(
    is_admission_offer_payment_ready(
        (select e from event e where e.event_id = :'readyEventID'),
        (select g from "group" g where g.group_id = :'readyGroupID'),
        1000,
        'stripe'
    ),
    true,
    'Should report a collectable paid seat as ready'
);

-- Should report an OCG01 readiness rejection as not ready
select is(
    is_admission_offer_payment_ready(
        (select e from event e where e.event_id = :'unnamedSellerEventID'),
        (select g from "group" g where g.group_id = :'unnamedSellerGroupID'),
        1000,
        'stripe'
    ),
    false,
    'Should report an OCG01 readiness rejection as not ready'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
