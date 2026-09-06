-- Tests recording application-fee adjustment provider outcomes.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd4020000-0000-0000-0000-000000000001'
\set eventCategoryID 'd4020000-0000-0000-0000-000000000002'
\set eventID 'd4020000-0000-0000-0000-000000000003'
\set groupCategoryID 'd4020000-0000-0000-0000-000000000004'
\set groupID 'd4020000-0000-0000-0000-000000000005'
\set purchaseRefundAdjustmentID 'd4020000-0000-0000-0000-000000000006'
\set purchaseRefundJobID 'd4020000-0000-0000-0000-000000000007'
\set purchaseRefundPurchaseID 'd4020000-0000-0000-0000-000000000008'
\set taxAdjustmentID 'd4020000-0000-0000-0000-000000000009'
\set taxJobID 'd4020000-0000-0000-0000-000000000010'
\set taxPurchaseID 'd4020000-0000-0000-0000-000000000011'
\set ticketTypeID 'd4020000-0000-0000-0000-000000000012'
\set userID 'd4020000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, user and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with the direct-charge purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by both purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Direct-charge purchases owning both adjustment kinds
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
    (2500, 'direct-charge', 'acct_d402', 'USD', :'eventID', :'purchaseRefundPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_purchase_refund_d4020000', 'ch_purchase_refund_d4020000', 'cs_purchase_refund_d4020000', 'acct_d402', 'pi_purchase_refund_d4020000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', 'acct_d402', 'USD', :'eventID', :'taxPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_tax_d4020000', 'ch_tax_d4020000', 'cs_tax_d4020000', 'acct_d402', 'pi_tax_d4020000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb);

-- Payment job for the purchase-refund adjustment
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'purchaseRefundPurchaseID', 'apply-fee-outcome-purchase-refund-d4020000',
    'event-purchase-application-fee-adjustment', :'purchaseRefundJobID',
    'stripe'
);

-- Payment job for the tax-reconciliation adjustment
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'taxPurchaseID', 'apply-fee-outcome-tax-d4020000',
    'event-purchase-application-fee-adjustment', :'taxJobID', 'stripe'
);

-- Purchase-refund adjustment that must not mark the purchase reconciled
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id
) values (
    80, :'purchaseRefundAdjustmentID', :'purchaseRefundPurchaseID',
    'purchase-refund', :'purchaseRefundJobID'
);

-- Tax-reconciliation adjustment that marks the purchase reconciled
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id
) values (
    20, :'taxAdjustmentID', :'taxPurchaseID', 'tax-reconciliation',
    :'taxJobID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should record a purchase-refund adjustment outcome without reconciling tax
select lives_ok(
    format($$
        select apply_event_purchase_application_fee_adjustment_outcome(
            epafa,
            'fr_purchase_refund_d4020000'
        )
        from event_purchase_application_fee_adjustment epafa
        where epafa.event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'purchaseRefundAdjustmentID'),
    'Should record a purchase-refund adjustment outcome without reconciling tax'
);
select results_eq(
    format($$
        select
            epafa.provider_application_fee_refund_id,
            ep.financially_reconciled_at
        from event_purchase_application_fee_adjustment epafa
        join event_purchase ep using (event_purchase_id)
        where epafa.event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'purchaseRefundAdjustmentID'),
    $$ values ('fr_purchase_refund_d4020000'::text, null::timestamptz) $$,
    'Should persist a purchase-refund adjustment outcome without reconciling tax'
);

-- Should record a tax adjustment outcome and mark the purchase reconciled
select lives_ok(
    format($$
        select apply_event_purchase_application_fee_adjustment_outcome(
            epafa,
            'fr_tax_d4020000'
        )
        from event_purchase_application_fee_adjustment epafa
        where epafa.event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'taxAdjustmentID'),
    'Should record a tax adjustment outcome and mark the purchase reconciled'
);
select results_eq(
    format($$
        select
            epafa.provider_application_fee_refund_id,
            ep.financially_reconciled_at is not null
        from event_purchase_application_fee_adjustment epafa
        join event_purchase ep using (event_purchase_id)
        where epafa.event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'taxAdjustmentID'),
    $$ values ('fr_tax_d4020000'::text, true) $$,
    'Should persist a tax adjustment outcome and mark the purchase reconciled'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
