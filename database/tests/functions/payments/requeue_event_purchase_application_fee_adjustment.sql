-- Tests requeueing exhausted application-fee adjustments.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adjustmentID 'd7400000-0000-0000-0000-000000000001'
\set communityID 'd7400000-0000-0000-0000-000000000002'
\set eventCategoryID 'd7400000-0000-0000-0000-000000000003'
\set eventID 'd7400000-0000-0000-0000-000000000004'
\set groupCategoryID 'd7400000-0000-0000-0000-000000000005'
\set groupID 'd7400000-0000-0000-0000-000000000006'
\set lowAdjustmentID 'd7400000-0000-0000-0000-000000000010'
\set lowPurchaseID 'd7400000-0000-0000-0000-000000000011'
\set lowUserID 'd7400000-0000-0000-0000-000000000016'
\set missingAdjustmentID 'd7400000-0000-0000-0000-000000000012'
\set missingGroupID 'd7400000-0000-0000-0000-000000000013'
\set pendingAdjustmentID 'd7400000-0000-0000-0000-000000000014'
\set pendingPurchaseID 'd7400000-0000-0000-0000-000000000015'
\set pendingUserID 'd7400000-0000-0000-0000-000000000017'
\set purchaseID 'd7400000-0000-0000-0000-000000000007'
\set ticketTypeID 'd7400000-0000-0000-0000-000000000008'
\set userID 'd7400000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the adjustment event
insert into community (
    banner_mobile_url, banner_url, community_id, description, display_name,
    logo_url, name
) values (
    'https://example.test/mobile.png', 'https://example.test/banner.png',
    :'communityID', 'Community', 'Community', 'https://example.test/logo.png',
    'requeue-fee-adjustment-community'
);

-- Event category used by the adjustment event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the adjustment group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the adjustment event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Attendees owning the direct-charge purchases
insert into "user" (auth_hash, email, user_id, username) values
    ('user', 'user@example.test', :'userID', 'user'),
    ('low-user', 'low-user@example.test', :'lowUserID', 'low-user'),
    ('pending-user', 'pending-user@example.test', :'pendingUserID', 'pending-user');

-- Event associated with the direct-charge purchases
insert into event (
    description, event_category_id, event_id, event_kind_id, group_id, name,
    payment_currency_code, slug, timezone
) values (
    'Event', :'eventCategoryID', :'eventID', 'in-person', :'groupID', 'Event',
    'USD', 'event', 'UTC'
);

-- Ticket type snapshotted by each purchase
insert into event_ticket_type (
    event_id, event_ticket_type_id, "order", seats_total, title
) values (:'eventID', :'ticketTypeID', 1, 10, 'General admission');

-- Purchases owning exhausted and ineligible adjustments
insert into event_purchase (
    amount_minor, charge_model, connected_seller_id, currency_code, event_id,
    event_purchase_id, event_ticket_type_id, final_platform_fee_amount_minor,
    payment_provider_id, provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_object_account_id,
    provider_payment_reference, provider_total_minor,
    provisional_platform_fee_amount_minor, seller_snapshot, status,
    subtotal_excluding_tax_minor, tax_amount_minor, tax_behavior,
    tax_calculation_mode, tax_classification, ticket_title, user_id,
    venue_snapshot
) values
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'purchaseID',
        :'ticketTypeID', 80, 'stripe', 'fee_adjust', 'ch_adjust', 'cs_adjust',
        'acct_fee', 'pi_adjust', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'userID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'lowPurchaseID',
        :'ticketTypeID', 80, 'stripe', 'fee_low', 'ch_low', 'cs_low',
        'acct_fee', 'pi_low', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'lowUserID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID',
        :'pendingPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_pending',
        'ch_pending', 'cs_pending', 'acct_fee', 'pi_pending', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'pendingUserID', '{}'::jsonb
    );

-- Exhausted, under-budget, and wrong-status adjustments
insert into event_purchase_application_fee_adjustment (
    amount_minor, attempt_count, event_purchase_application_fee_adjustment_id,
    event_purchase_id, failure_message, idempotency_key, kind, status
) values
    (
        20, 10, :'adjustmentID', :'purchaseID', 'automatic attempts exhausted',
        'requeue-fee-adjustment', 'tax-reconciliation', 'failed'
    ),
    (
        20, 9, :'lowAdjustmentID', :'lowPurchaseID', 'provider unavailable',
        'requeue-low-fee-adjustment', 'purchase-refund', 'failed'
    ),
    (
        20, 10, :'pendingAdjustmentID', :'pendingPurchaseID', null,
        'requeue-pending-fee-adjustment', 'tax-reconciliation', 'pending'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a missing application-fee adjustment
select throws_ok(
    format(
        'select requeue_event_purchase_application_fee_adjustment(%L, %L)',
        :'groupID', :'missingAdjustmentID'
    ),
    'retryable application-fee adjustment not found',
    'Should reject a missing application-fee adjustment'
);

-- Should reject an application-fee adjustment from another group
select throws_ok(
    format(
        'select requeue_event_purchase_application_fee_adjustment(%L, %L)',
        :'missingGroupID', :'adjustmentID'
    ),
    'retryable application-fee adjustment not found',
    'Should reject an application-fee adjustment from another group'
);

-- Should reject application-fee work before automatic retries are exhausted
select throws_ok(
    format(
        'select requeue_event_purchase_application_fee_adjustment(%L, %L)',
        :'groupID', :'lowAdjustmentID'
    ),
    'retryable application-fee adjustment not found',
    'Should reject application-fee work before automatic retries are exhausted'
);

-- Should reject application-fee work with a non-failed status
select throws_ok(
    format(
        'select requeue_event_purchase_application_fee_adjustment(%L, %L)',
        :'groupID', :'pendingAdjustmentID'
    ),
    'retryable application-fee adjustment not found',
    'Should reject application-fee work with a non-failed status'
);

-- Should requeue an exhausted application-fee adjustment
select lives_ok(
    format(
        'select requeue_event_purchase_application_fee_adjustment(%L, %L)',
        :'groupID', :'adjustmentID'
    ),
    'Should requeue an exhausted application-fee adjustment'
);

-- Should reset application-fee work for another bounded attempt cycle
select results_eq(
    format($$
        select attempt_count, failure_message, status
        from event_purchase_application_fee_adjustment
        where event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'adjustmentID'),
    $$ values (0, null::text, 'pending'::text) $$,
    'Should reset application-fee work for another bounded attempt cycle'
);

-- Should preserve every rejected application-fee work item
select results_eq(
    format($$
        select event_purchase_application_fee_adjustment_id, attempt_count, status
        from event_purchase_application_fee_adjustment
        where event_purchase_application_fee_adjustment_id in (%L::uuid, %L::uuid)
        order by event_purchase_application_fee_adjustment_id
    $$, :'lowAdjustmentID', :'pendingAdjustmentID'),
    format(
        $$ values
            (%L::uuid, 9, 'failed'::text),
            (%L::uuid, 10, 'pending'::text)
        $$,
        :'lowAdjustmentID', :'pendingAdjustmentID'
    ),
    'Should preserve every rejected application-fee work item'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
