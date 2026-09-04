-- Tests validating admission offer payment readiness.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f30b0000-0000-0000-0000-000000000001'
\set eventCategoryID 'f30b0000-0000-0000-0000-000000000002'
\set externalFreeEventID 'f30b0000-0000-0000-0000-000000000003'
\set externalPaidEventID 'f30b0000-0000-0000-0000-000000000004'
\set externalUnreadyEventID 'f30b0000-0000-0000-0000-000000000005'
\set groupCategoryID 'f30b0000-0000-0000-0000-000000000006'
\set nonExternalFreeEventID 'f30b0000-0000-0000-0000-000000000007'
\set nonExternalPaidEventID 'f30b0000-0000-0000-0000-000000000008'
\set readyGroupID 'f30b0000-0000-0000-0000-000000000009'
\set stripeGroupID 'f30b0000-0000-0000-0000-00000000000a'
\set unreadyGroupID 'f30b0000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and categories
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

-- Operator allowlist used by the external-ready event
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Allowlisted group with external payments enabled
select fx_group(:'readyGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true
));

-- Group with the matching Stripe payment recipient
select fx_group(:'stripeGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_validate_offer',
        'seller_display_name', 'Validate Offer Seller'
    )
));

-- Group outside the external-payments allowlist
select fx_group(:'unreadyGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'US',
    'external_payments_enabled', true
));

-- External event used by the free unready and paid unready branches
select fx_event(:'externalFreeEventID', :'unreadyGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/validate-admission-offer-free'
));

-- External event whose group is eligible for paid external payments
select fx_event(:'externalPaidEventID', :'readyGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/validate-admission-offer-ready'
));

-- External event whose group is not eligible for paid external payments
select fx_event(:'externalUnreadyEventID', :'unreadyGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/validate-admission-offer-unready'
));

-- Non-external free event that does not need server payment configuration
select fx_event(:'nonExternalFreeEventID', :'stripeGroupID', :'eventCategoryID');

-- Non-external paid event with complete venue and currency context
select fx_event(:'nonExternalPaidEventID', :'stripeGroupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'in-person',
    'payment_currency_code', 'USD',
    'venue_address', '1 Validation Way',
    'venue_city', 'Validation City',
    'venue_country_code', 'US',
    'venue_name', 'Validation Hall',
    'venue_zip_code', '12345'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow external free offers without payment readiness
select lives_ok(
    format(
        $$select validate_admission_offer_payment_readiness((select e from event e where e.event_id = %L::uuid), (select g from "group" g where g.group_id = %L::uuid), 0, null)$$,
        :'externalFreeEventID',
        :'unreadyGroupID'
    ),
    'Should allow external free offers without payment readiness'
);

-- Should allow external paid offers when event is ready
select lives_ok(
    format(
        $$select validate_admission_offer_payment_readiness((select e from event e where e.event_id = %L::uuid), (select g from "group" g where g.group_id = %L::uuid), 1000, null)$$,
        :'externalPaidEventID',
        :'readyGroupID'
    ),
    'Should allow external paid offers when event is ready'
);

-- Should allow non-external free offers without server payments
select lives_ok(
    format(
        $$select validate_admission_offer_payment_readiness((select e from event e where e.event_id = %L::uuid), (select g from "group" g where g.group_id = %L::uuid), 0, null)$$,
        :'nonExternalFreeEventID',
        :'stripeGroupID'
    ),
    'Should allow non-external free offers without server payments'
);

-- Should allow non-external paid offers with matching Stripe recipient
select lives_ok(
    format(
        $$select validate_admission_offer_payment_readiness((select e from event e where e.event_id = %L::uuid), (select g from "group" g where g.group_id = %L::uuid), 1000, 'stripe')$$,
        :'nonExternalPaidEventID',
        :'stripeGroupID'
    ),
    'Should allow non-external paid offers with matching Stripe recipient'
);

-- Should reject external paid offers when the group is ineligible
select throws_ok(
    format(
        $$select validate_admission_offer_payment_readiness((select e from event e where e.event_id = %L::uuid), (select g from "group" g where g.group_id = %L::uuid), 1000, null)$$,
        :'externalUnreadyEventID',
        :'unreadyGroupID'
    ),
    'OCG01',
    'external payments are not available for this event',
    'Should reject external paid offers when the group is ineligible'
);

-- Should reject non-external paid offers without server payments
select throws_ok(
    format(
        $$select validate_admission_offer_payment_readiness((select e from event e where e.event_id = %L::uuid), (select g from "group" g where g.group_id = %L::uuid), 1000, null)$$,
        :'nonExternalPaidEventID',
        :'stripeGroupID'
    ),
    'OCG01',
    'payments are not configured on this server',
    'Should reject non-external paid offers without server payments'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
