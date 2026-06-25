-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '79270000-0000-0000-0000-000000000001'
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

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'validate-context-alliance',
    'Validate Context Alliance',
    'Test',
    'https://e/banner-mobile.png',
    'https://e/banner.png',
    'https://e/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Tech');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

-- Groups
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    payment_recipient
)
values
    (
        :'missingRecipientGroupID',
        :'allianceID',
        :'groupCategoryID',
        'Missing Recipient Group',
        'missing-recipient-group',
        null
    ),
    (
        :'nonStripeGroupID',
        :'allianceID',
        :'groupCategoryID',
        'Non Stripe Group',
        'non-stripe-group',
        jsonb_build_object('provider', 'paypal', 'recipient_id', 'merchant_non_stripe')
    ),
    (
        :'validGroupID',
        :'allianceID',
        :'groupCategoryID',
        'Valid Group',
        'valid-group',
        jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_validate_context')
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
    ends_at,
    starts_at,
    payment_currency_code,
    published,
    published_at,
    registration_starts_at
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
    null,
    now() + interval '1 day',
    'USD',
    false,
    null,
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
    null,
    now() + interval '1 day',
    null,
    true,
    now(),
    null
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
    null,
    now() + interval '1 day',
    'USD',
    true,
    now(),
    null
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
    null,
    now() + interval '1 day',
    'USD',
    true,
    now(),
    null
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
    null,
    now() + interval '1 day',
    'USD',
    true,
    now(),
    null
), (
    false,
    :'invalidCurrencyEventID',
    :'eventCategoryID',
    'in-person',
    :'validGroupID',
    'Invalid Currency Event',
    'invalid-currency-event',
    'Test event',
    'UTC',
    null,
    now() + interval '1 day',
    'USDD',
    true,
    now(),
    null
), (
    false,
    :'openUntilStartEventID',
    :'eventCategoryID',
    'in-person',
    :'validGroupID',
    'Open Until Start Event',
    'open-until-start-event',
    'Test event',
    'UTC',
    now() + interval '1 hour',
    now() - interval '1 hour',
    'USD',
    true,
    now(),
    now() - interval '2 hours'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the payment currency for a valid event context
select is(
    prepare_event_checkout_validate_event(:'allianceID'::uuid, :'validEventID'::uuid, 'stripe'),
    'USD',
    'Should return the payment currency for a valid event context'
);

-- Should reject groups without a configured payments recipient
select throws_ok(
    format($$select prepare_event_checkout_validate_event(
        %L::uuid,
        %L::uuid,
        'stripe'
    )$$, :'allianceID', :'missingRecipientEventID'),
    'group payments recipient is not configured',
    'Should reject groups without a configured payments recipient'
);

-- Should reject events when payments are not configured on the server
select throws_ok(
    format($$select prepare_event_checkout_validate_event(
        %L::uuid,
        %L::uuid,
        null
    )$$, :'allianceID', :'validEventID'),
    'payments are not configured on this server',
    'Should reject events when payments are not configured on the server'
);

-- Should reject groups whose payments recipient does not match the server provider
select throws_ok(
    format($$select prepare_event_checkout_validate_event(
        %L::uuid,
        %L::uuid,
        'stripe'
    )$$, :'allianceID', :'nonStripeEventID'),
    'group payments recipient is not configured for the server payments provider',
    'Should reject groups whose payments recipient does not match the server provider'
);

-- Should reject ticketed events without a payment currency
select throws_ok(
    format($$select prepare_event_checkout_validate_event(
        %L::uuid,
        %L::uuid,
        'stripe'
    )$$, :'allianceID', :'missingCurrencyEventID'),
    'ticketed event is missing payment_currency_code',
    'Should reject ticketed events without a payment currency'
);

-- Should reject inactive events
select throws_ok(
    format($$select prepare_event_checkout_validate_event(
        %L::uuid,
        %L::uuid,
        'stripe'
    )$$, :'allianceID', :'inactiveEventID'),
    'event not found or inactive',
    'Should reject inactive events'
);

-- Should return the payment currency after an open-only registration window reaches the event start
select is(
    prepare_event_checkout_validate_event(
        :'communityID'::uuid,
        :'openUntilStartEventID'::uuid,
        'stripe'
    ),
    'USD',
    'Should return the payment currency after an open-only registration window reaches the event start'
);

-- Should reject events whose currency code is unsupported
select throws_ok(
    format($$select prepare_event_checkout_validate_event(
        %L::uuid,
        %L::uuid,
        'stripe'
    )$$, :'allianceID', :'invalidCurrencyEventID'),
    'payment_currency_code must be a supported currency code',
    'Should reject events whose currency code is unsupported'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
