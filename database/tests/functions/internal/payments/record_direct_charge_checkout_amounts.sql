-- Tests recording authoritative direct-charge checkout amounts.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adjustmentPurchaseID 'f3120000-0000-0000-0000-000000000001'
\set adjustmentUserID 'f3120000-0000-0000-0000-000000000002'
\set communityID 'f3120000-0000-0000-0000-000000000003'
\set eventCategoryID 'f3120000-0000-0000-0000-000000000004'
\set eventID 'f3120000-0000-0000-0000-000000000005'
\set groupCategoryID 'f3120000-0000-0000-0000-000000000006'
\set groupID 'f3120000-0000-0000-0000-000000000007'
\set matchedPurchaseID 'f3120000-0000-0000-0000-000000000008'
\set matchedUserID 'f3120000-0000-0000-0000-000000000009'
\set ticketTypeID 'f3120000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'adjustmentUserID');
select fx_user(:'matchedUserID');

-- Group with direct-charge payment recipient
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_record_direct_charge_checkout_amounts'
    )
));

-- Event hosting pending direct-charge purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Ticket type shared by direct-charge purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'Record direct-charge admission'
));

-- Pending direct-charge purchases awaiting authoritative provider amounts
insert into event_purchase (
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    provider_application_fee_id,
    provider_checkout_session_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values
    (
        999,
        'direct-charge',
        'acct_record_direct_charge_checkout_amounts',
        'USD',
        :'eventID',
        :'adjustmentPurchaseID',
        :'ticketTypeID',
        current_timestamp + interval '1 hour',
        'stripe',
        250,
        30,
        null,
        'record-direct-charge-checkout-amounts-session-adjustment',
        'acct_record_direct_charge_checkout_amounts',
        '{"connected_account_id":"acct_record_direct_charge_checkout_amounts","display_name":"Record Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        'exclusive',
        'manual',
        'professional-event-admission',
        'Adjustment admission',
        :'adjustmentUserID',
        '{}'::jsonb
    ),
    (
        1000,
        'direct-charge',
        'acct_record_direct_charge_checkout_amounts',
        'USD',
        :'eventID',
        :'matchedPurchaseID',
        :'ticketTypeID',
        current_timestamp + interval '1 hour',
        'stripe',
        250,
        25,
        'record-direct-charge-checkout-amounts-fee-recorded',
        'record-direct-charge-checkout-amounts-session-matched',
        'acct_record_direct_charge_checkout_amounts',
        '{"connected_account_id":"acct_record_direct_charge_checkout_amounts","display_name":"Record Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        'exclusive',
        'manual',
        'professional-event-admission',
        'Matched admission',
        :'matchedUserID',
        '{}'::jsonb
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Record amounts for a purchase whose final fee matches the provisional fee
select record_direct_charge_checkout_amounts(
    (select ep from event_purchase ep where ep.event_purchase_id = :'matchedPurchaseID'),
    'record-direct-charge-checkout-amounts-charge-matched',
    null,
    1100,
    100
);

-- Should reconcile purchases whose final fee already matches
select results_eq(
    format(
        $$
            select
                ep.final_platform_fee_amount_minor,
                ep.financially_reconciled_at is not null,
                ep.provider_application_fee_id,
                ep.provider_charge_id,
                ep.provider_total_minor,
                ep.subtotal_excluding_tax_minor,
                ep.tax_amount_minor,
                (
                    select count(*)::int
                    from event_purchase_application_fee_adjustment epafa
                    where epafa.event_purchase_id = ep.event_purchase_id
                )
            from event_purchase ep
            where ep.event_purchase_id = %L::uuid
        $$,
        :'matchedPurchaseID'
    ),
    $$ values (
        25::bigint,
        true,
        'record-direct-charge-checkout-amounts-fee-recorded'::text,
        'record-direct-charge-checkout-amounts-charge-matched'::text,
        1100::bigint,
        1000::bigint,
        100::bigint,
        0::int
    ) $$,
    'Should reconcile purchases whose final fee already matches'
);

-- Record amounts for a purchase whose final fee needs a tax adjustment
select record_direct_charge_checkout_amounts(
    (select ep from event_purchase ep where ep.event_purchase_id = :'adjustmentPurchaseID'),
    'record-direct-charge-checkout-amounts-charge-adjustment',
    'record-direct-charge-checkout-amounts-fee-reported',
    1099,
    100
);

-- Should persist authoritative amounts and reported application fees
select results_eq(
    format(
        $$
            select
                final_platform_fee_amount_minor,
                financially_reconciled_at is null,
                provider_application_fee_id,
                provider_charge_id,
                provider_total_minor,
                subtotal_excluding_tax_minor,
                tax_amount_minor
            from event_purchase
            where event_purchase_id = %L::uuid
        $$,
        :'adjustmentPurchaseID'
    ),
    $$ values (
        24::bigint,
        true,
        'record-direct-charge-checkout-amounts-fee-reported'::text,
        'record-direct-charge-checkout-amounts-charge-adjustment'::text,
        1099::bigint,
        999::bigint,
        100::bigint
    ) $$,
    'Should persist authoritative amounts and reported application fees'
);

-- Should queue one tax reconciliation fee adjustment
select results_eq(
    format(
        $$
            select
                epafa.amount_minor,
                epafa.kind,
                pj.idempotency_key,
                pj.kind,
                pj.status
            from event_purchase_application_fee_adjustment epafa
            join payment_job pj on pj.payment_job_id = epafa.payment_job_id
            where epafa.event_purchase_id = %L::uuid
        $$,
        :'adjustmentPurchaseID'
    ),
    format(
        $$ values (
            6::bigint,
            'tax-reconciliation'::text,
            'event-purchase-tax-fee-adjustment-%s'::text,
            'event-purchase-application-fee-adjustment'::text,
            'pending'::text
        ) $$,
        :'adjustmentPurchaseID'
    ),
    'Should queue one tax reconciliation fee adjustment'
);

-- Replay the amount recording to verify the adjustment stays idempotent
select record_direct_charge_checkout_amounts(
    (select ep from event_purchase ep where ep.event_purchase_id = :'adjustmentPurchaseID'),
    'record-direct-charge-checkout-amounts-charge-adjustment',
    'record-direct-charge-checkout-amounts-fee-reported',
    1099,
    100
);

-- Should not duplicate tax reconciliation fee adjustments
select is(
    (
        select count(*)::int
        from event_purchase_application_fee_adjustment
        where event_purchase_id = :'adjustmentPurchaseID'
        and kind = 'tax-reconciliation'
    ),
    1,
    'Should not duplicate tax reconciliation fee adjustments'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
