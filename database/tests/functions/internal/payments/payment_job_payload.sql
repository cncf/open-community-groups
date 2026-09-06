-- Tests payment job worker payloads.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set applicationAdjustmentID 'd40c0000-0000-0000-0000-000000000001'
\set applicationJobID 'd40c0000-0000-0000-0000-000000000002'
\set communityID 'd40c0000-0000-0000-0000-000000000003'
\set creditJobID 'd40c0000-0000-0000-0000-000000000004'
\set creditNoteID 'd40c0000-0000-0000-0000-000000000005'
\set eventCategoryID 'd40c0000-0000-0000-0000-000000000006'
\set eventID 'd40c0000-0000-0000-0000-000000000007'
\set groupCategoryID 'd40c0000-0000-0000-0000-000000000008'
\set groupID 'd40c0000-0000-0000-0000-000000000009'
\set missingCreditContextCreditNoteID 'd40c0000-0000-0000-0000-000000000010'
\set missingCreditContextJobID 'd40c0000-0000-0000-0000-000000000011'
\set missingCreditContextPurchaseID 'd40c0000-0000-0000-0000-000000000012'
\set missingCreditContextRefundID 'd40c0000-0000-0000-0000-000000000013'
\set missingCreditContextRefundJobID 'd40c0000-0000-0000-0000-000000000014'
\set missingDomainJobID 'd40c0000-0000-0000-0000-000000000015'
\set missingEventPurchaseID 'd40c0000-0000-0000-0000-000000000016'
\set missingFeeContextAdjustmentID 'd40c0000-0000-0000-0000-000000000017'
\set missingFeeContextJobID 'd40c0000-0000-0000-0000-000000000018'
\set missingFeeContextPurchaseID 'd40c0000-0000-0000-0000-000000000019'
\set missingSellerJobID 'd40c0000-0000-0000-0000-000000000020'
\set missingSellerPurchaseID 'd40c0000-0000-0000-0000-000000000021'
\set missingSellerRefundID 'd40c0000-0000-0000-0000-000000000022'
\set refundID 'd40c0000-0000-0000-0000-000000000023'
\set refundJobID 'd40c0000-0000-0000-0000-000000000024'
\set successPurchaseID 'd40c0000-0000-0000-0000-000000000025'
\set ticketTypeID 'd40c0000-0000-0000-0000-000000000026'
\set unknownJobID 'd40c0000-0000-0000-0000-000000000027'
\set userID 'd40c0000-0000-0000-0000-000000000028'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, user and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with payload purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by payload purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 20,
    'title', 'General admission'
));

-- Direct-charge purchases covering complete and incomplete provider context
insert into event_purchase (
    amount_minor, charge_model, completed_at, connected_seller_id,
    currency_code, event_id, event_purchase_id, event_ticket_type_id,
    final_platform_fee_amount_minor, payment_provider_id,
    provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_invoice_id,
    provider_object_account_id, provider_payment_reference,
    provider_total_minor, provisional_platform_fee_amount_minor,
    seller_snapshot, status, subtotal_excluding_tax_minor, tax_amount_minor,
    tax_behavior, tax_calculation_mode, tax_classification, ticket_title,
    user_id, venue_snapshot
) values
    (2500, 'direct-charge', current_timestamp, 'acct_d40c', 'USD', :'eventID', :'missingCreditContextPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_missing_credit_d40c0000', 'ch_missing_credit_d40c0000', 'cs_missing_credit_d40c0000', null, 'acct_d40c', 'pi_missing_credit_d40c0000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d40c', 'USD', :'eventID', :'missingFeeContextPurchaseID', :'ticketTypeID', 80, 'stripe', null, 'ch_missing_fee_d40c0000', 'cs_missing_fee_d40c0000', 'in_missing_fee_d40c0000', 'acct_d40c', 'pi_missing_fee_d40c0000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d40c', 'USD', :'eventID', :'successPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_success_d40c0000', 'ch_success_d40c0000', 'cs_success_d40c0000', 'in_success_d40c0000', 'acct_d40c', 'pi_success_d40c0000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb);

-- External purchase missing connected-seller context for refund payloads
insert into event_purchase (
    amount_minor, charge_model, currency_code, event_id, event_purchase_id,
    event_ticket_type_id, platform_fee_bps,
    provisional_platform_fee_amount_minor, status, ticket_title, user_id
) values (
    2500, 'external', 'USD', :'eventID', :'missingSellerPurchaseID',
    :'ticketTypeID', 0, 0, 'completed', 'External admission', :'userID'
);

-- Application-fee payment job with complete provider context
insert into payment_job (
    attempt_count, event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id, status
) values (
    2, :'successPurchaseID', 'payment-job-payload-application-d40c0000',
    'event-purchase-application-fee-adjustment', :'applicationJobID',
    'stripe', 'failed'
);

-- Credit-note payment job with complete provider context
insert into payment_job (
    attempt_count, event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    3, :'successPurchaseID', 'payment-job-payload-credit-d40c0000',
    'event-purchase-credit-note', :'creditJobID', 'stripe'
);

-- Credit-note payment job missing invoice and refund provider context
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'missingCreditContextPurchaseID',
    'payment-job-payload-credit-missing-context-d40c0000',
    'event-purchase-credit-note', :'missingCreditContextJobID', 'stripe'
);

-- Refund payment job behind the missing credit-note context
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'missingCreditContextPurchaseID',
    'payment-job-payload-credit-refund-missing-context-d40c0000',
    'event-purchase-refund', :'missingCreditContextRefundJobID', 'stripe'
);

-- Application-fee payment job missing provider fee context
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'missingFeeContextPurchaseID',
    'payment-job-payload-application-missing-context-d40c0000',
    'event-purchase-application-fee-adjustment', :'missingFeeContextJobID',
    'stripe'
);

-- Refund payment job with complete provider context
insert into payment_job (
    attempt_count, event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    4, :'successPurchaseID', 'payment-job-payload-refund-d40c0000',
    'event-purchase-refund', :'refundJobID', 'stripe'
);

-- Refund payment job whose purchase lacks connected-seller context
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'missingSellerPurchaseID',
    'payment-job-payload-refund-missing-seller-d40c0000',
    'event-purchase-refund', :'missingSellerJobID', 'stripe'
);

-- Provider-confirmed refund used by refund and credit-note payloads
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, provider_refund_id,
    provider_refunded_at, status, terminal_failure
) values (
    2500, 'USD', :'successPurchaseID', :'refundID', 'event-cancellation',
    :'refundJobID', 'stripe', 're_success_d40c0000',
    '2024-01-01 00:00:00+00', 'provider-succeeded', false
);

-- Unconfirmed refund used by the missing credit-note context
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, status, terminal_failure
) values (
    2500, 'USD', :'missingCreditContextPurchaseID',
    :'missingCreditContextRefundID', 'event-cancellation',
    :'missingCreditContextRefundJobID', 'stripe', 'provider-pending', false
);

-- Refund used to reach the missing connected-seller validation
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, status, terminal_failure
) values (
    2500, 'USD', :'missingSellerPurchaseID', :'missingSellerRefundID',
    'event-cancellation', :'missingSellerJobID', 'stripe', 'provider-pending',
    false
);

-- Application-fee adjustment with complete provider context
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id
) values (
    80, :'applicationAdjustmentID', :'successPurchaseID', 'purchase-refund',
    :'applicationJobID'
);

-- Application-fee adjustment missing immutable provider context
insert into event_purchase_application_fee_adjustment (
    amount_minor, event_purchase_application_fee_adjustment_id,
    event_purchase_id, kind, payment_job_id
) values (
    80, :'missingFeeContextAdjustmentID', :'missingFeeContextPurchaseID',
    'purchase-refund', :'missingFeeContextJobID'
);

-- Credit note with complete provider context
insert into event_purchase_credit_note (
    amount_minor, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, payment_job_id, payment_provider_id,
    provider_object_account_id, tax_amount_minor
) values (
    2500, 'USD', :'creditNoteID', :'refundID', :'creditJobID', 'stripe',
    'acct_d40c', 200
);

-- Credit note missing immutable provider context
insert into event_purchase_credit_note (
    amount_minor, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, payment_job_id, payment_provider_id,
    provider_object_account_id, tax_amount_minor
) values (
    2500, 'USD', :'missingCreditContextCreditNoteID',
    :'missingCreditContextRefundID', :'missingCreditContextJobID', 'stripe',
    'acct_d40c', 200
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should build an application-fee adjustment payload
select is(
    (
        select payment_job_payload(pj)
        from payment_job pj
        where pj.payment_job_id = :'applicationJobID'::uuid
    ),
    jsonb_build_object(
        'application_fee_adjustment', jsonb_build_object(
            'amount_minor', 80,
            'connected_seller_id', 'acct_d40c',
            'currency_code', 'USD',
            'event_purchase_application_fee_adjustment_id', :'applicationAdjustmentID'::uuid,
            'kind', 'purchase-refund',
            'provider_application_fee_id', 'fee_success_d40c0000'
        )
    ),
    'Should build an application-fee adjustment payload'
);

-- Should build a credit-note payload
select is(
    (
        select payment_job_payload(pj)
        from payment_job pj
        where pj.payment_job_id = :'creditJobID'::uuid
    ),
    jsonb_build_object(
        'credit_note', jsonb_build_object(
            'amount_minor', 2500,
            'connected_seller_id', 'acct_d40c',
            'event_purchase_credit_note_id', :'creditNoteID'::uuid,
            'event_purchase_refund_id', :'refundID'::uuid,
            'provider_invoice_id', 'in_success_d40c0000',
            'provider_refund_id', 're_success_d40c0000',
            'tax_amount_minor', 200
        )
    ),
    'Should build a credit-note payload'
);

-- Should build a refund payload with notification context
select is(
    (
        select payment_job_payload(pj)
        from payment_job pj
        where pj.payment_job_id = :'refundJobID'::uuid
    ),
    jsonb_build_object(
        'refund', jsonb_build_object(
            'amount_minor', 2500,
            'attempt_count', 4,
            'community_id', :'communityID'::uuid,
            'connected_seller_id', 'acct_d40c',
            'currency_code', 'USD',
            'event_id', :'eventID'::uuid,
            'event_purchase_id', :'successPurchaseID'::uuid,
            'event_purchase_refund_id', :'refundID'::uuid,
            'idempotency_key', 'payment-job-payload-refund-d40c0000',
            'kind', 'event-cancellation',
            'payment_job_id', :'refundJobID'::uuid,
            'payment_provider', 'stripe',
            'provider_payment_reference', 'pi_success_d40c0000',
            'provider_refund_id', 're_success_d40c0000',
            'provider_refunded_at', 1704067200,
            'status', 'provider-succeeded',
            'terminal_failure', false
        )
    ),
    'Should build a refund payload with notification context'
);

-- Should reject application-fee jobs without a domain row
select throws_ok(
    format($$
        select payment_job_payload(jsonb_populate_record(null::payment_job, jsonb_build_object(
            'event_purchase_id', %L,
            'kind', 'event-purchase-application-fee-adjustment',
            'payment_job_id', %L
        )))
    $$, :'successPurchaseID', :'missingDomainJobID'),
    'application-fee adjustment not found',
    'Should reject application-fee jobs without a domain row'
);

-- Should reject application-fee jobs without provider context
select throws_ok(
    format($$
        select payment_job_payload(pj)
        from payment_job pj
        where pj.payment_job_id = %L::uuid
    $$, :'missingFeeContextJobID'),
    'application-fee adjustment is missing provider context',
    'Should reject application-fee jobs without provider context'
);

-- Should reject credit-note jobs without a domain row
select throws_ok(
    format($$
        select payment_job_payload(jsonb_populate_record(null::payment_job, jsonb_build_object(
            'event_purchase_id', %L,
            'kind', 'event-purchase-credit-note',
            'payment_job_id', %L
        )))
    $$, :'successPurchaseID', :'missingDomainJobID'),
    'credit note not found',
    'Should reject credit-note jobs without a domain row'
);

-- Should reject credit-note jobs without provider context
select throws_ok(
    format($$
        select payment_job_payload(pj)
        from payment_job pj
        where pj.payment_job_id = %L::uuid
    $$, :'missingCreditContextJobID'),
    'credit note is missing provider context',
    'Should reject credit-note jobs without provider context'
);

-- Should reject jobs whose purchase is missing
select throws_ok(
    format($$
        select payment_job_payload(jsonb_populate_record(null::payment_job, jsonb_build_object(
            'event_purchase_id', %L,
            'kind', 'event-purchase-refund',
            'payment_job_id', %L
        )))
    $$, :'missingEventPurchaseID', :'missingDomainJobID'),
    'event purchase not found',
    'Should reject jobs whose purchase is missing'
);

-- Should reject refund jobs without a domain row
select throws_ok(
    format($$
        select payment_job_payload(jsonb_populate_record(null::payment_job, jsonb_build_object(
            'event_purchase_id', %L,
            'kind', 'event-purchase-refund',
            'payment_job_id', %L
        )))
    $$, :'successPurchaseID', :'missingDomainJobID'),
    'event purchase refund not found',
    'Should reject refund jobs without a domain row'
);

-- Should reject refund jobs without connected-seller context
select throws_ok(
    format($$
        select payment_job_payload(pj)
        from payment_job pj
        where pj.payment_job_id = %L::uuid
    $$, :'missingSellerJobID'),
    'event purchase is missing connected seller account',
    'Should reject refund jobs without connected-seller context'
);

-- Should reject unknown payment job kinds
select throws_ok(
    format($$
        select payment_job_payload(jsonb_populate_record(null::payment_job, jsonb_build_object(
            'event_purchase_id', %L,
            'kind', 'unknown',
            'payment_job_id', %L
        )))
    $$, :'successPurchaseID', :'unknownJobID'),
    'payment job kind has no worker payload',
    'Should reject unknown payment job kinds'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
