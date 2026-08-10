-- Tests externally completing exhausted application-fee adjustments.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'd7420000-0000-0000-0000-000000000001'
\set adjustmentID 'd7420000-0000-0000-0000-000000000002'
\set buyerID 'd7420000-0000-0000-0000-000000000003'
\set communityID 'd7420000-0000-0000-0000-000000000004'
\set eventCategoryID 'd7420000-0000-0000-0000-000000000005'
\set eventID 'd7420000-0000-0000-0000-000000000006'
\set groupCategoryID 'd7420000-0000-0000-0000-000000000007'
\set groupID 'd7420000-0000-0000-0000-000000000008'
\set lowAdjustmentID 'd7420000-0000-0000-0000-000000000011'
\set lowBuyerID 'd7420000-0000-0000-0000-000000000017'
\set lowPurchaseID 'd7420000-0000-0000-0000-000000000012'
\set missingAdjustmentID 'd7420000-0000-0000-0000-000000000013'
\set missingGroupID 'd7420000-0000-0000-0000-000000000014'
\set pendingAdjustmentID 'd7420000-0000-0000-0000-000000000015'
\set pendingBuyerID 'd7420000-0000-0000-0000-000000000018'
\set pendingPurchaseID 'd7420000-0000-0000-0000-000000000016'
\set purchaseID 'd7420000-0000-0000-0000-000000000009'
\set ticketTypeID 'd7420000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the recovery event
insert into community (
    banner_mobile_url, banner_url, community_id, description, display_name,
    logo_url, name
) values (
    'https://example.test/mobile.png', 'https://example.test/banner.png',
    :'communityID', 'Community', 'Community', 'https://example.test/logo.png',
    'recover-fee-adjustment-community'
);

-- Event category used by the recovery event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the recovery group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the recovery event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Event manager and attendees used by recovery scenarios
insert into "user" (auth_hash, email, user_id, username) values
    ('actor', 'actor@example.test', :'actorID', 'actor'),
    ('buyer', 'buyer@example.test', :'buyerID', 'buyer'),
    ('low-buyer', 'low-buyer@example.test', :'lowBuyerID', 'low-buyer'),
    (
        'pending-buyer', 'pending-buyer@example.test', :'pendingBuyerID',
        'pending-buyer'
    );

-- Events-manager membership granting recovery authority
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'events-manager', :'actorID');

-- Event associated with each direct-charge purchase
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

-- Purchases owning recoverable and ineligible adjustments
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
        'General admission', :'buyerID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'lowPurchaseID',
        :'ticketTypeID', 80, 'stripe', 'fee_low', 'ch_low', 'cs_low',
        'acct_fee', 'pi_low', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'lowBuyerID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_fee', 'USD', :'eventID',
        :'pendingPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_pending',
        'ch_pending', 'cs_pending', 'acct_fee', 'pi_pending', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'pendingBuyerID', '{}'::jsonb
    );

-- Exhausted, under-budget, and wrong-status adjustments
insert into event_purchase_application_fee_adjustment (
    amount_minor, attempt_count, event_purchase_application_fee_adjustment_id,
    event_purchase_id, failure_message, idempotency_key, kind, status
) values
    (
        20, 10, :'adjustmentID', :'purchaseID', 'automatic attempts exhausted',
        'recover-fee-adjustment', 'tax-reconciliation', 'failed'
    ),
    (
        20, 9, :'lowAdjustmentID', :'lowPurchaseID', 'provider unavailable',
        'recover-low-fee-adjustment', 'purchase-refund', 'failed'
    ),
    (
        20, 10, :'pendingAdjustmentID', :'pendingPurchaseID', null,
        'recover-pending-fee-adjustment', 'tax-reconciliation', 'pending'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject partial application-fee recovery evidence
select throws_ok(
    format($$
        update event_purchase_application_fee_adjustment
        set recovery_reference = 'case-partial'
        where event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'adjustmentID'),
    '23514',
    null,
    'Should reject partial application-fee recovery evidence'
);

-- Should require an actor user id
select throws_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(null, %L, %L, %L, %L, %L)',
        :'groupID', :'adjustmentID', 'fr_external', 'case-123',
        'Verified Stripe activity'
    ),
    'actor user id is required',
    'Should require an actor user id'
);

-- Should require a group id
select throws_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(%L, null, %L, %L, %L, %L)',
        :'actorID', :'adjustmentID', 'fr_external', 'case-123',
        'Verified Stripe activity'
    ),
    'group id is required',
    'Should require a group id'
);

-- Should require a provider application-fee refund id
select throws_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'adjustmentID', '   ', 'case-123',
        'Verified Stripe activity'
    ),
    'provider application-fee refund id is required',
    'Should require a provider application-fee refund id'
);

-- Should require a recovery reference
select throws_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'adjustmentID', 'fr_external', '   ',
        'Verified Stripe activity'
    ),
    'recovery reference is required',
    'Should require a recovery reference'
);

-- Should require a recovery note
select throws_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'adjustmentID', 'fr_external', 'case-123',
        '   '
    ),
    'recovery note is required',
    'Should require a recovery note'
);

-- Should reject a missing application-fee adjustment
select throws_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'missingAdjustmentID', 'fr_external',
        'case-123', 'Verified Stripe activity'
    ),
    'recoverable application-fee adjustment not found',
    'Should reject a missing application-fee adjustment'
);

-- Should reject an application-fee adjustment from another group
select throws_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'missingGroupID', :'adjustmentID', 'fr_external',
        'case-123', 'Verified Stripe activity'
    ),
    'recoverable application-fee adjustment not found',
    'Should reject an application-fee adjustment from another group'
);

-- Should require events write access at execution time
select throws_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(%L, %L, %L, %L, %L, %L)',
        :'buyerID', :'groupID', :'adjustmentID', 'fr_external', 'case-123',
        'Verified Stripe activity'
    ),
    'events write access is required',
    'Should require events write access at execution time'
);

-- Should reject application-fee work before automatic attempts are exhausted
select throws_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'lowAdjustmentID', 'fr_external', 'case-123',
        'Verified Stripe activity'
    ),
    'recoverable application-fee adjustment not found',
    'Should reject application-fee work before automatic attempts are exhausted'
);

-- Should reject application-fee work with a non-failed status
select throws_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'pendingAdjustmentID', 'fr_external',
        'case-123', 'Verified Stripe activity'
    ),
    'recoverable application-fee adjustment not found',
    'Should reject application-fee work with a non-failed status'
);

-- Should complete an application-fee adjustment resolved in Stripe
select lives_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'adjustmentID', 'fr_external', 'case-123',
        'Verified Stripe activity'
    ),
    'Should complete an application-fee adjustment resolved in Stripe'
);

-- Should store provider identity and recovery evidence while reconciling tax
select results_eq(
    format($$
        select
            a.attempt_count,
            a.failure_message,
            a.provider_application_fee_refund_id,
            a.recovery_completed_at is not null,
            a.recovery_completed_by_user_id,
            a.recovery_note,
            a.recovery_reference,
            a.status,
            p.financially_reconciled_at is not null
        from event_purchase_application_fee_adjustment a
        join event_purchase p using (event_purchase_id)
        where a.event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'adjustmentID'),
    format(
        $$ values (
            10, null::text, %L::text, true, %L::uuid, %L::text, %L::text,
            'completed'::text, true
        ) $$,
        'fr_external', :'actorID', 'Verified Stripe activity', 'case-123'
    ),
    'Should store provider identity and recovery evidence while reconciling tax'
);

-- Should audit the application-fee recovery evidence
select results_eq(
    $$ select action, details->>'recovery_reference' from audit_log $$,
    $$ values (
        'event_application_fee_adjustment_recovery_completed'::text,
        'case-123'::text
    ) $$,
    'Should audit the application-fee recovery evidence'
);

-- Should accept an exact recovery completion replay
select lives_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'adjustmentID', 'fr_external', 'case-123',
        'Verified Stripe activity'
    ),
    'Should accept an exact recovery completion replay'
);

-- Should reject conflicting application-fee recovery evidence
select throws_ok(
    format(
        'select complete_event_purchase_application_fee_adjustment_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'adjustmentID', 'fr_other', 'case-123',
        'Verified Stripe activity'
    ),
    'application-fee recovery already completed with different evidence',
    'Should reject conflicting application-fee recovery evidence'
);

-- Should preserve every rejected application-fee work item
select results_eq(
    format($$
        select
            event_purchase_application_fee_adjustment_id,
            attempt_count,
            status
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
