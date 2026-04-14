-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79270000-0000-0000-0000-000000000001'
\set eventCategoryID '79270000-0000-0000-0000-000000000002'
\set validEventID '79270000-0000-0000-0000-000000000003'
\set missingRecipientEventID '79270000-0000-0000-0000-000000000004'
\set nonStripeEventID '79270000-0000-0000-0000-000000000005'
\set missingCurrencyEventID '79270000-0000-0000-0000-000000000006'
\set inactiveEventID '79270000-0000-0000-0000-000000000007'
\set validGroupID '79270000-0000-0000-0000-000000000008'
\set missingRecipientGroupID '79270000-0000-0000-0000-000000000009'
\set nonStripeGroupID '79270000-0000-0000-0000-000000000010'
\set groupCategoryID '79270000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'validate-context-community', 'Validate Context Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, payment_recipient, slug) values
    (
        :'missingRecipientGroupID',
        :'communityID',
        :'groupCategoryID',
        'Missing Recipient Group',
        null,
        'missing-recipient-group'
    ),
    (
        :'nonStripeGroupID',
        :'communityID',
        :'groupCategoryID',
        'Non Stripe Group',
        jsonb_build_object('provider', 'paypal', 'recipient_id', 'merchant_non_stripe'),
        'non-stripe-group'
    ),
    (
        :'validGroupID',
        :'communityID',
        :'groupCategoryID',
        'Valid Group',
        jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_validate_context'),
        'valid-group'
    );

-- Events
insert into event (
    canceled,
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    starts_at,
    payment_currency_code,
    published,
    published_at
) values (
    false,
    :'inactiveEventID',
    :'eventCategoryID',
    'in-person',
    :'validGroupID',
    'Inactive Event',
    'inactive-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    false,
    null
), (
    false,
    :'missingCurrencyEventID',
    :'eventCategoryID',
    'in-person',
    :'validGroupID',
    'Missing Currency Event',
    'missing-currency-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    null,
    true,
    now()
), (
    false,
    :'missingRecipientEventID',
    :'eventCategoryID',
    'in-person',
    :'missingRecipientGroupID',
    'Missing Recipient Event',
    'missing-recipient-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
), (
    false,
    :'nonStripeEventID',
    :'eventCategoryID',
    'in-person',
    :'nonStripeGroupID',
    'Non Stripe Event',
    'non-stripe-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
), (
    false,
    :'validEventID',
    :'eventCategoryID',
    'in-person',
    :'validGroupID',
    'Valid Event',
    'valid-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the payment currency for a valid event context
select is(
    prepare_event_checkout_validate_event(:'communityID'::uuid, :'validEventID'::uuid, 'stripe'),
    'USD',
    'Should return the payment currency for a valid event context'
);

-- Should reject groups without a configured payments recipient
select throws_ok(
    $$select prepare_event_checkout_validate_event(
        '79270000-0000-0000-0000-000000000001'::uuid,
        '79270000-0000-0000-0000-000000000004'::uuid,
        'stripe'
    )$$,
    'group payments recipient is not configured',
    'Should reject groups without a configured payments recipient'
);

-- Should reject events when payments are not configured on the server
select throws_ok(
    $$select prepare_event_checkout_validate_event(
        '79270000-0000-0000-0000-000000000001'::uuid,
        '79270000-0000-0000-0000-000000000003'::uuid,
        null
    )$$,
    'payments are not configured on this server',
    'Should reject events when payments are not configured on the server'
);

-- Should reject groups whose payments recipient does not match the server provider
select throws_ok(
    $$select prepare_event_checkout_validate_event(
        '79270000-0000-0000-0000-000000000001'::uuid,
        '79270000-0000-0000-0000-000000000005'::uuid,
        'stripe'
    )$$,
    'group payments recipient is not configured for the server payments provider',
    'Should reject groups whose payments recipient does not match the server provider'
);

-- Should reject ticketed events without a payment currency
select throws_ok(
    $$select prepare_event_checkout_validate_event(
        '79270000-0000-0000-0000-000000000001'::uuid,
        '79270000-0000-0000-0000-000000000006'::uuid,
        'stripe'
    )$$,
    'ticketed event is missing payment_currency_code',
    'Should reject ticketed events without a payment currency'
);

-- Should reject inactive events
select throws_ok(
    $$select prepare_event_checkout_validate_event(
        '79270000-0000-0000-0000-000000000001'::uuid,
        '79270000-0000-0000-0000-000000000007'::uuid,
        'stripe'
    )$$,
    'event not found or inactive',
    'Should reject inactive events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
