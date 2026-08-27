-- Tests claiming durable application-fee adjustments.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adjustmentID 'd7320000-0000-0000-0000-000000000001'
\set blockedAdjustmentID 'd7320000-0000-0000-0000-000000000020'
\set blockedPurchaseID 'd7320000-0000-0000-0000-000000000021'
\set blockedUserID 'd7320000-0000-0000-0000-000000000022'
\set communityID 'd7320000-0000-0000-0000-000000000002'
\set eventCategoryID 'd7320000-0000-0000-0000-000000000003'
\set eventID 'd7320000-0000-0000-0000-000000000004'
\set finalAdjustmentID 'd7320000-0000-0000-0000-000000000010'
\set finalPurchaseID 'd7320000-0000-0000-0000-000000000011'
\set finalUserID 'd7320000-0000-0000-0000-000000000017'
\set groupCategoryID 'd7320000-0000-0000-0000-000000000005'
\set groupID 'd7320000-0000-0000-0000-000000000006'
\set purchaseID 'd7320000-0000-0000-0000-000000000007'
\set retryAdjustmentID 'd7320000-0000-0000-0000-000000000012'
\set retryPurchaseID 'd7320000-0000-0000-0000-000000000013'
\set retryUserID 'd7320000-0000-0000-0000-000000000018'
\set staleAdjustmentID 'd7320000-0000-0000-0000-000000000014'
\set staleClaimID 'd7320000-0000-0000-0000-000000000015'
\set stalePurchaseID 'd7320000-0000-0000-0000-000000000016'
\set staleUserID 'd7320000-0000-0000-0000-000000000019'
\set ticketTypeID 'd7320000-0000-0000-0000-000000000008'
\set userID 'd7320000-0000-0000-0000-000000000009'

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
    'claim-fee-adjustment-community'
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
    ('blocked-user', 'blocked-user@example.test', :'blockedUserID', 'blocked-user'),
    ('final-user', 'final-user@example.test', :'finalUserID', 'final-user'),
    ('retry-user', 'retry-user@example.test', :'retryUserID', 'retry-user'),
    ('stale-user', 'stale-user@example.test', :'staleUserID', 'stale-user');

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

-- Purchases providing immutable context for each claim state
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
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'blockedPurchaseID',
        :'ticketTypeID', 80, 'stripe', null, 'ch_blocked', 'cs_blocked',
        'acct_fee', 'pi_blocked', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'blockedUserID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'purchaseID',
        :'ticketTypeID', 80, 'stripe', 'fee_adjust', 'ch_adjust', 'cs_adjust',
        'acct_fee', 'pi_adjust', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'userID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'retryPurchaseID',
        :'ticketTypeID', 80, 'stripe', 'fee_retry', 'ch_retry', 'cs_retry',
        'acct_fee', 'pi_retry', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'retryUserID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'stalePurchaseID',
        :'ticketTypeID', 80, 'stripe', 'fee_stale', 'ch_stale', 'cs_stale',
        'acct_fee', 'pi_stale', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'staleUserID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'finalPurchaseID',
        :'ticketTypeID', 80, 'stripe', 'fee_final', 'ch_final', 'cs_final',
        'acct_fee', 'pi_final', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'finalUserID', '{}'::jsonb
    );

-- Pending, retryable, stale, and exhausted claim fixtures
insert into event_purchase_application_fee_adjustment (
    amount_minor, attempt_count, claim_id, claimed_at, created_at,
    event_purchase_application_fee_adjustment_id, event_purchase_id,
    failure_message, idempotency_key, kind, next_attempt_at, status
) values
    (
        20, 0, null, null, '2023-12-31 00:00:00+00', :'blockedAdjustmentID',
        :'blockedPurchaseID', null, 'claim-blocked-fee-adjustment',
        'tax-reconciliation', '2023-12-31 00:00:00+00', 'pending'
    ),
    (
        20, 0, null, null, '2024-01-01 00:00:00+00', :'adjustmentID',
        :'purchaseID', null, 'claim-fee-adjustment', 'tax-reconciliation',
        '2024-01-01 00:00:00+00', 'pending'
    ),
    (
        80, 1, null, null, '2024-01-02 00:00:00+00', :'retryAdjustmentID',
        :'retryPurchaseID', 'provider unavailable', 'claim-retry-fee-adjustment',
        'purchase-refund', '2024-01-02 00:00:00+00', 'failed'
    ),
    (
        20, 1, :'staleClaimID', current_timestamp - interval '16 minutes',
        '2024-01-03 00:00:00+00', :'staleAdjustmentID', :'stalePurchaseID',
        null, 'claim-stale-fee-adjustment', 'tax-reconciliation',
        '2024-01-03 00:00:00+00', 'processing'
    ),
    (
        80, 10, gen_random_uuid(), current_timestamp - interval '16 minutes',
        '2024-01-04 00:00:00+00', :'finalAdjustmentID', :'finalPurchaseID',
        'provider timed out', 'claim-final-fee-adjustment', 'purchase-refund',
        '2024-01-04 00:00:00+00', 'processing'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should skip work waiting for its fee identifier and claim complete context
create temporary table first_claim as
select claim_event_purchase_application_fee_adjustment('stripe') as item;
select results_eq(
    $$
        select
            item->>'amount_minor',
            (
                select attempt_count::text
                from event_purchase_application_fee_adjustment
                where event_purchase_application_fee_adjustment_id =
                    (item->>'event_purchase_application_fee_adjustment_id')::uuid
            ),
            (item->>'claim_id') is not null,
            item->>'connected_seller_id',
            item->>'currency_code',
            item->>'event_purchase_application_fee_adjustment_id',
            item->>'event_purchase_id',
            item->>'idempotency_key',
            item->>'kind',
            item->>'provider_application_fee_id'
        from first_claim
    $$,
    format(
        $$ values (
            '20'::text, '1'::text, true, 'acct_fee'::text, 'USD'::text,
            %L::text, %L::text, 'claim-fee-adjustment'::text,
            'tax-reconciliation'::text, 'fee_adjust'::text
        ) $$,
        :'adjustmentID', :'purchaseID'
    ),
    'Should skip work waiting for its fee identifier and claim complete context'
);

-- Should claim failed application-fee work as the next retry attempt
create temporary table retry_claim as
select claim_event_purchase_application_fee_adjustment('stripe') as item;
select results_eq(
    $$
        select
            (
                select attempt_count::text
                from event_purchase_application_fee_adjustment
                where event_purchase_application_fee_adjustment_id =
                    (item->>'event_purchase_application_fee_adjustment_id')::uuid
            ),
            item->>'event_purchase_application_fee_adjustment_id'
        from retry_claim
    $$,
    format($$ values ('2'::text, %L::text) $$, :'retryAdjustmentID'),
    'Should claim failed application-fee work as the next retry attempt'
);

-- Should reclaim an abandoned application-fee claim below the attempt limit
create temporary table stale_claim as
select claim_event_purchase_application_fee_adjustment('stripe') as item;
select results_eq(
    $$
        select
            (
                select attempt_count::text
                from event_purchase_application_fee_adjustment
                where event_purchase_application_fee_adjustment_id =
                    (item->>'event_purchase_application_fee_adjustment_id')::uuid
            ),
            item->>'event_purchase_application_fee_adjustment_id'
        from stale_claim
    $$,
    format($$ values ('2'::text, %L::text) $$, :'staleAdjustmentID'),
    'Should reclaim an abandoned application-fee claim below the attempt limit'
);

-- Should not reclaim an abandoned final automatic attempt
select is(
    claim_event_purchase_application_fee_adjustment('stripe'),
    null,
    'Should not reclaim an abandoned final automatic attempt'
);

-- Should surface an abandoned final application-fee attempt for operator action
select results_eq(
    format($$
        select attempt_count, claim_id, failure_message, status
        from event_purchase_application_fee_adjustment
        where event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'finalAdjustmentID'),
    $$ values (
        10,
        null::uuid,
        E'provider timed out\nApplication-fee adjustment worker claim expired after the final automatic attempt; provider outcome is unknown'::text,
        'failed'::text
    ) $$,
    'Should surface an abandoned final application-fee attempt for operator action'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
