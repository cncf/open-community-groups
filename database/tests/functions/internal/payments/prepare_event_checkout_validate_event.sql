-- Tests locking and validating events before checkout.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79270000-0000-0000-0000-000000000001'
\set eventCategoryID '79270000-0000-0000-0000-000000000002'
\set groupCategoryID '79270000-0000-0000-0000-000000000011'
\set inactiveEventID '79270000-0000-0000-0000-000000000007'
\set invalidCurrencyEventID '79270000-0000-0000-0000-000000000012'
\set missingCurrencyEventID '79270000-0000-0000-0000-000000000006'
\set missingRecipientEventID '79270000-0000-0000-0000-000000000004'
\set missingRecipientGroupID '79270000-0000-0000-0000-000000000009'
\set nonStripeEventID '79270000-0000-0000-0000-000000000005'
\set nonStripeGroupID '79270000-0000-0000-0000-000000000010'
\set openUntilStartEventID '79270000-0000-0000-0000-000000000013'
\set validEventID '79270000-0000-0000-0000-000000000003'
\set validGroupID '79270000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'missingRecipientGroupID', :'communityID', :'groupCategoryID');

-- Groups
select fx_group(:'nonStripeGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
            'provider', 'paypal',
            'recipient_id', 'merchant_non_stripe',
            'seller_display_name', 'Non-Stripe Fiscal Sponsor'
        )));
select fx_group(:'validGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
            'provider', 'stripe',
            'recipient_id', 'acct_validate_context',
            'seller_display_name', 'Validate Context Fiscal Sponsor'
        )));

-- Events
select fx_event(:'inactiveEventID', :'validGroupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'starts_at', now() + interval '1 day'
));
select fx_event(:'missingCurrencyEventID', :'validGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));
select fx_event(:'missingRecipientEventID', :'missingRecipientGroupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));
select fx_event(:'nonStripeEventID', :'nonStripeGroupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));
select fx_event(:'validEventID', :'validGroupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));
select fx_event(:'invalidCurrencyEventID', :'validGroupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USDD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));
select fx_event(:'openUntilStartEventID', :'validGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 hour',
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'registration_starts_at', now() - interval '2 hours',
    'starts_at', now() - interval '1 hour'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the payment currency for a valid event context
select is(
    (prepare_event_checkout_validate_event(:'communityID'::uuid, :'validEventID'::uuid)).payment_currency_code,
    'USD',
    'Should return the payment currency for a valid event context'
);

-- Should return the locked event row
select is(
    (prepare_event_checkout_validate_event(:'communityID'::uuid, :'validEventID'::uuid)).event_id,
    :'validEventID'::uuid,
    'Should return the locked event row'
);

-- Should allow groups without a configured payments recipient
select is(
    (prepare_event_checkout_validate_event(
        :'communityID'::uuid,
        :'missingRecipientEventID'::uuid
    )).payment_currency_code,
    'USD',
    'Should leave payment recipient validation until after pricing'
);

-- Should allow recipients for another provider during state validation
select is(
    (prepare_event_checkout_validate_event(
        :'communityID'::uuid,
        :'nonStripeEventID'::uuid
    )).payment_currency_code,
    'USD',
    'Should leave provider compatibility validation until after pricing'
);

-- Should return a null currency for intrinsically free event checkout
select is(
    (prepare_event_checkout_validate_event(
        :'communityID'::uuid,
        :'missingCurrencyEventID'::uuid
    )).payment_currency_code,
    null::text,
    'Should leave currency requirements until after pricing'
);

-- Should reject inactive events
select throws_ok(
    format($$select prepare_event_checkout_validate_event(
        %L::uuid,
        %L::uuid
    )$$, :'communityID', :'inactiveEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject inactive events'
);

-- Should return the payment currency after an open-only registration window reaches the event start
select is(
    (prepare_event_checkout_validate_event(
        :'communityID'::uuid,
        :'openUntilStartEventID'::uuid
    )).payment_currency_code,
    'USD',
    'Should return the payment currency after an open-only registration window reaches the event start'
);

-- Should return unsupported currency unchanged until a paid price is resolved
select is(
    (prepare_event_checkout_validate_event(
        :'communityID'::uuid,
        :'invalidCurrencyEventID'::uuid
    )).payment_currency_code,
    'USDD',
    'Should leave currency validation until after pricing'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
