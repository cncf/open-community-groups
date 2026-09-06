-- Tests payment job domain readiness.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set applicationBlockedJobID 'd40a0000-0000-0000-0000-000000000001'
\set applicationBlockedPurchaseID 'd40a0000-0000-0000-0000-000000000002'
\set applicationReadyJobID 'd40a0000-0000-0000-0000-000000000003'
\set applicationReadyPurchaseID 'd40a0000-0000-0000-0000-000000000004'
\set communityID 'd40a0000-0000-0000-0000-000000000005'
\set creditBlockedCreditNoteID 'd40a0000-0000-0000-0000-000000000006'
\set creditBlockedJobID 'd40a0000-0000-0000-0000-000000000007'
\set creditBlockedPurchaseID 'd40a0000-0000-0000-0000-000000000008'
\set creditBlockedRefundID 'd40a0000-0000-0000-0000-000000000009'
\set creditBlockedRefundJobID 'd40a0000-0000-0000-0000-000000000010'
\set creditReadyCreditNoteID 'd40a0000-0000-0000-0000-000000000011'
\set creditReadyJobID 'd40a0000-0000-0000-0000-000000000012'
\set creditReadyPurchaseID 'd40a0000-0000-0000-0000-000000000013'
\set creditReadyRefundID 'd40a0000-0000-0000-0000-000000000014'
\set creditReadyRefundJobID 'd40a0000-0000-0000-0000-000000000015'
\set eventCategoryID 'd40a0000-0000-0000-0000-000000000016'
\set eventID 'd40a0000-0000-0000-0000-000000000017'
\set groupCategoryID 'd40a0000-0000-0000-0000-000000000018'
\set groupID 'd40a0000-0000-0000-0000-000000000019'
\set refundReadyID 'd40a0000-0000-0000-0000-000000000020'
\set refundReadyJobID 'd40a0000-0000-0000-0000-000000000021'
\set refundReadyPurchaseID 'd40a0000-0000-0000-0000-000000000022'
\set refundTerminalID 'd40a0000-0000-0000-0000-000000000023'
\set refundTerminalJobID 'd40a0000-0000-0000-0000-000000000024'
\set refundTerminalPurchaseID 'd40a0000-0000-0000-0000-000000000025'
\set ticketTypeID 'd40a0000-0000-0000-0000-000000000026'
\set unknownJobID 'd40a0000-0000-0000-0000-000000000027'
\set userID 'd40a0000-0000-0000-0000-000000000028'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, user and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with readiness purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket type snapshotted by readiness purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 20,
    'title', 'General admission'
));

-- Purchases covering ready and blocked domain states
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
    (2500, 'direct-charge', current_timestamp, 'acct_d40a', 'USD', :'eventID', :'applicationBlockedPurchaseID', :'ticketTypeID', 80, 'stripe', null, 'ch_application_blocked_d40a0000', 'cs_application_blocked_d40a0000', 'in_application_blocked_d40a0000', 'acct_d40a', 'pi_application_blocked_d40a0000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d40a', 'USD', :'eventID', :'applicationReadyPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_application_ready_d40a0000', 'ch_application_ready_d40a0000', 'cs_application_ready_d40a0000', 'in_application_ready_d40a0000', 'acct_d40a', 'pi_application_ready_d40a0000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d40a', 'USD', :'eventID', :'creditBlockedPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_credit_blocked_d40a0000', 'ch_credit_blocked_d40a0000', 'cs_credit_blocked_d40a0000', 'in_credit_blocked_d40a0000', 'acct_d40a', 'pi_credit_blocked_d40a0000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d40a', 'USD', :'eventID', :'creditReadyPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_credit_ready_d40a0000', 'ch_credit_ready_d40a0000', 'cs_credit_ready_d40a0000', 'in_credit_ready_d40a0000', 'acct_d40a', 'pi_credit_ready_d40a0000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d40a', 'USD', :'eventID', :'refundReadyPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_refund_ready_d40a0000', 'ch_refund_ready_d40a0000', 'cs_refund_ready_d40a0000', 'in_refund_ready_d40a0000', 'acct_d40a', 'pi_refund_ready_d40a0000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refund-pending', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_d40a', 'USD', :'eventID', :'refundTerminalPurchaseID', :'ticketTypeID', 80, 'stripe', 'fee_refund_terminal_d40a0000', 'ch_refund_terminal_d40a0000', 'cs_refund_terminal_d40a0000', 'in_refund_terminal_d40a0000', 'acct_d40a', 'pi_refund_terminal_d40a0000', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refund-recovery-pending', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb);

-- Application-fee payment job blocked by missing provider fee
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'applicationBlockedPurchaseID', 'payment-job-ready-application-blocked-d40a0000',
    'event-purchase-application-fee-adjustment', :'applicationBlockedJobID',
    'stripe'
);

-- Application-fee payment job with provider fee context
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'applicationReadyPurchaseID', 'payment-job-ready-application-ready-d40a0000',
    'event-purchase-application-fee-adjustment', :'applicationReadyJobID',
    'stripe'
);

-- Refund payment job behind a blocked credit note
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'creditBlockedPurchaseID', 'payment-job-ready-credit-refund-blocked-d40a0000',
    'event-purchase-refund', :'creditBlockedRefundJobID', 'stripe'
);

-- Credit-note payment job blocked by a refund without provider confirmation
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'creditBlockedPurchaseID', 'payment-job-ready-credit-blocked-d40a0000',
    'event-purchase-credit-note', :'creditBlockedJobID', 'stripe'
);

-- Refund payment job behind a ready credit note
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'creditReadyPurchaseID', 'payment-job-ready-credit-refund-ready-d40a0000',
    'event-purchase-refund', :'creditReadyRefundJobID', 'stripe'
);

-- Credit-note payment job whose refund has provider confirmation
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'creditReadyPurchaseID', 'payment-job-ready-credit-ready-d40a0000',
    'event-purchase-credit-note', :'creditReadyJobID', 'stripe'
);

-- Refund payment job that remains eligible
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'refundReadyPurchaseID', 'payment-job-ready-refund-ready-d40a0000',
    'event-purchase-refund', :'refundReadyJobID', 'stripe'
);

-- Refund payment job blocked by terminal provider failure
insert into payment_job (
    event_purchase_id, idempotency_key, kind, payment_job_id,
    payment_provider_id
) values (
    :'refundTerminalPurchaseID', 'payment-job-ready-refund-terminal-d40a0000',
    'event-purchase-refund', :'refundTerminalJobID', 'stripe'
);

-- Refund without provider confirmation behind the blocked credit note
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, status, terminal_failure
) values (
    2500, 'USD', :'creditBlockedPurchaseID', :'creditBlockedRefundID',
    'event-cancellation', :'creditBlockedRefundJobID', 'stripe',
    'provider-pending', false
);

-- Provider-confirmed refund behind the ready credit note
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, provider_refund_id,
    provider_refunded_at, status, terminal_failure
) values (
    2500, 'USD', :'creditReadyPurchaseID', :'creditReadyRefundID',
    'event-cancellation', :'creditReadyRefundJobID', 'stripe',
    're_credit_ready_d40a0000', current_timestamp, 'provider-succeeded',
    false
);

-- Refund that workers may still process
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, status, terminal_failure
) values (
    2500, 'USD', :'refundReadyPurchaseID', :'refundReadyID',
    'event-cancellation', :'refundReadyJobID', 'stripe', 'provider-pending',
    false
);

-- Terminal refund that requires operator recovery
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    kind, payment_job_id, payment_provider_id, provider_refund_id, status,
    terminal_failure
) values (
    2500, 'USD', :'refundTerminalPurchaseID', :'refundTerminalID',
    'event-cancellation', :'refundTerminalJobID', 'stripe',
    're_refund_terminal_d40a0000', 'provider-failed', true
);

-- Credit note blocked by an unconfirmed refund
insert into event_purchase_credit_note (
    amount_minor, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, payment_job_id, payment_provider_id,
    provider_object_account_id, tax_amount_minor
) values (
    2500, 'USD', :'creditBlockedCreditNoteID', :'creditBlockedRefundID',
    :'creditBlockedJobID', 'stripe', 'acct_d40a', 200
);

-- Credit note ready after its refund is confirmed
insert into event_purchase_credit_note (
    amount_minor, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, payment_job_id, payment_provider_id,
    provider_object_account_id, tax_amount_minor
) values (
    2500, 'USD', :'creditReadyCreditNoteID', :'creditReadyRefundID',
    :'creditReadyJobID', 'stripe', 'acct_d40a', 200
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should classify readiness by payment job kind and provider outcome
select results_eq(
    format($$
        select label, payment_job_is_ready(job)
        from (
            select 'application blocked'::text as label, pj as job
            from payment_job pj
            where pj.payment_job_id = %L::uuid
            union all
            select 'application ready'::text, pj
            from payment_job pj
            where pj.payment_job_id = %L::uuid
            union all
            select 'credit blocked'::text, pj
            from payment_job pj
            where pj.payment_job_id = %L::uuid
            union all
            select 'credit ready'::text, pj
            from payment_job pj
            where pj.payment_job_id = %L::uuid
            union all
            select 'refund ready'::text, pj
            from payment_job pj
            where pj.payment_job_id = %L::uuid
            union all
            select 'refund terminal'::text, pj
            from payment_job pj
            where pj.payment_job_id = %L::uuid
            union all
            select 'unknown kind'::text, jsonb_populate_record(
                null::payment_job,
                jsonb_build_object(
                    'kind', 'unknown',
                    'payment_job_id', %L
                )
            )
        ) as scenarios
        order by label
    $$,
        :'applicationBlockedJobID',
        :'applicationReadyJobID',
        :'creditBlockedJobID',
        :'creditReadyJobID',
        :'refundReadyJobID',
        :'refundTerminalJobID',
        :'unknownJobID'
    ),
    $$ values
        ('application blocked'::text, false),
        ('application ready'::text, true),
        ('credit blocked'::text, false),
        ('credit ready'::text, true),
        ('refund ready'::text, true),
        ('refund terminal'::text, false),
        ('unknown kind'::text, false)
    $$,
    'Should classify readiness by payment job kind and provider outcome'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
