-- Tests loading authoritative event context for refund recovery.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79540000-0000-0000-0000-000000000001'
\set eventCategoryID '79540000-0000-0000-0000-000000000002'
\set eventID '79540000-0000-0000-0000-000000000003'
\set finalizedPurchaseID '79540000-0000-0000-0000-000000000004'
\set finalizedRefundID '79540000-0000-0000-0000-000000000005'
\set groupCategoryID '79540000-0000-0000-0000-000000000006'
\set groupID '79540000-0000-0000-0000-000000000007'
\set missingPurchaseID '79540000-0000-0000-0000-000000000008'
\set otherGroupID '79540000-0000-0000-0000-000000000009'
\set pendingPurchaseID '79540000-0000-0000-0000-000000000010'
\set pendingRefundID '79540000-0000-0000-0000-000000000011'
\set ticketTypeID '79540000-0000-0000-0000-000000000012'
\set userID '79540000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the recovery purchases
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
    'https://example.test/banner-mobile.png',
    'https://example.test/banner.png',
    'Refund recovery context community',
    'Refund Recovery Context Community',
    'https://example.test/logo.png',
    'refund-recovery-context-community'
);

-- Event category used by the recovery event
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Events');

-- Group category used by both recovery groups
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Groups');

-- Buyer whose refunds require recovery
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (
    :'userID',
    'refund-recovery-context',
    'refund-recovery-context@example.test',
    true,
    'refund-recovery-context'
);

-- Group containing the recovery event
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Refund Recovery Context Group',
    'refund-recovery-context-group'
);

-- Different group used to verify ownership scoping
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'otherGroupID',
    :'communityID',
    :'groupCategoryID',
    'Other Refund Recovery Context Group',
    'other-refund-recovery-context-group'
);

-- Event containing both recovery purchases
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone,

    payment_currency_code,
    published_at
) values (
    :'eventID',
    'Refund recovery context event',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Refund Recovery Context Event',
    true,
    'refund-recovery-context-event',
    current_timestamp + interval '1 day',
    'UTC',

    'USD',
    current_timestamp
);

-- Ticket type purchased before both refunds
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

-- Purchases before and after local refund finalization
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    payment_provider_id,
    provider_payment_reference,
    refunded_at
) values (
    :'finalizedPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'ticketTypeID',
    'refund-recovery-pending',
    'General admission',
    :'userID',

    'stripe',
    'pi_refund_recovery_context_finalized',
    '2024-02-01 10:00:00+00'
), (
    :'pendingPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'ticketTypeID',
    'refund-pending',
    'General admission',
    :'userID',

    'stripe',
    'pi_refund_recovery_context_pending',
    null
);

-- Provider failures before and after local finalization
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status,
    terminal_failure,

    failure_message,
    finalized_at,
    provider_refund_id
) values (
    :'finalizedRefundID',
    2500,
    'USD',
    :'finalizedPurchaseID',
    'event-purchase-refund-recovery-context-finalized',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-failed',
    true,

    'provider refund failed',
    '2024-02-01 10:00:00+00',
    're_refund_recovery_context_finalized'
), (
    :'pendingRefundID',
    2500,
    'USD',
    :'pendingPurchaseID',
    'event-purchase-refund-recovery-context-pending',
    'event-cancellation',
    'stripe',
    'provider-failed',
    true,

    'provider refund failed',
    null,
    're_refund_recovery_context_pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a missing purchase
select throws_ok(
    format(
        $$select get_event_purchase_refund_recovery_context(%L::uuid, %L::uuid)$$,
        :'groupID',
        :'missingPurchaseID'
    ),
    'event purchase refund not found',
    'Should reject a missing purchase'
);

-- Should reject a purchase outside the requested group
select throws_ok(
    format(
        $$select get_event_purchase_refund_recovery_context(%L::uuid, %L::uuid)$$,
        :'otherGroupID',
        :'pendingPurchaseID'
    ),
    'event purchase refund not found',
    'Should reject a purchase outside the requested group'
);

-- Should return context after local finalization
select is(
    get_event_purchase_refund_recovery_context(
        :'groupID'::uuid,
        :'finalizedPurchaseID'::uuid
    ),
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'event_purchase_refund_id', :'finalizedRefundID'::uuid,

        'notification_required', false
    ),
    'Should return context after local finalization'
);

-- Should return context before local finalization
select is(
    get_event_purchase_refund_recovery_context(
        :'groupID'::uuid,
        :'pendingPurchaseID'::uuid
    ),
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'event_purchase_refund_id', :'pendingRefundID'::uuid,

        'notification_required', true
    ),
    'Should return context before local finalization'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
