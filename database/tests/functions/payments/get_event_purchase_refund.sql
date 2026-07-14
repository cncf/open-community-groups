-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79530000-0000-0000-0000-000000000001'
\set eventCategoryID '79530000-0000-0000-0000-000000000002'
\set eventID '79530000-0000-0000-0000-000000000003'
\set groupCategoryID '79530000-0000-0000-0000-000000000004'
\set groupID '79530000-0000-0000-0000-000000000005'
\set missingPurchaseID '79530000-0000-0000-0000-000000000010'
\set purchaseID '79530000-0000-0000-0000-000000000008'
\set refundID '79530000-0000-0000-0000-000000000009'
\set ticketTypeID '79530000-0000-0000-0000-000000000006'
\set userID '79530000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the recovery purchase
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'Test community',
    'Refund Recovery Community',
    'https://example.com/logo.png',
    'refund-recovery-community'
);

-- Event category used by the recovery event
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Group category used by the recovery group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Buyer whose finalized refund requires recovery
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash', 'recovery@example.com', true, 'recovery-user');

-- Group containing the recovery event
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Refund Recovery Group',
    'refund-recovery-group'
);

-- Ticketed event containing the recovery purchase
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    published_at,
    slug,
    starts_at,
    timezone
) values (
    :'eventID',
    'Test event',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Refund Recovery Event',
    'USD',
    true,
    current_timestamp,
    'refund-recovery-event',
    current_timestamp + interval '1 day',
    'UTC'
);

-- Ticket type purchased before the refund
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeID',
    :'eventID',
    1,
    10,
    'General admission'
);

-- Purchase waiting for manual refund recovery
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    provider_payment_reference,
    refunded_at
) values (
    :'purchaseID',
    2500,
    'USD',
    0,
    :'eventID',
    :'ticketTypeID',
    'refund-recovery-pending',
    'General admission',
    :'userID',

    'pi_recovery_123',
    current_timestamp
);

-- Durable refund preserving the completed local finalization
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status,

    failure_message,
    finalized_at
) values (
    :'refundID',
    2500,
    'USD',
    :'purchaseID',
    'event-purchase-refund-recovery',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-failed',

    'provider refund failed: re_failed_123',
    '2024-02-01 10:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should load a durable post-finalization recovery refund
select is(
    get_event_purchase_refund(:'purchaseID'::uuid),
    jsonb_build_object(
        'amount_minor', 2500,
        'currency_code', 'USD',
        'event_purchase_id', :'purchaseID'::uuid,
        'event_purchase_refund_id', :'refundID'::uuid,
        'idempotency_key', 'event-purchase-refund-recovery',
        'kind', 'automatic-unfulfillable-checkout',
        'payment_provider', 'stripe',
        'status', 'provider-failed',

        'failure_message', 'provider refund failed: re_failed_123',
        'finalized_at', 1706781600,

        'started_now', false
    ),
    'Should load a durable post-finalization recovery refund'
);

-- Should reject a purchase without a durable refund
select throws_ok(
    format(
        $$select get_event_purchase_refund(%L::uuid)$$,
        :'missingPurchaseID'
    ),
    'event purchase refund not found',
    'Should reject a purchase without a durable refund'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
