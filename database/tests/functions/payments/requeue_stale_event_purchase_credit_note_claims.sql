-- Tests recovery of credit-note claims abandoned by interrupted workers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd7450000-0000-0000-0000-000000000001'
\set eventCategoryID 'd7450000-0000-0000-0000-000000000002'
\set eventID 'd7450000-0000-0000-0000-000000000003'
\set failedCreditNoteID 'd7450000-0000-0000-0000-000000000004'
\set failedPurchaseID 'd7450000-0000-0000-0000-000000000005'
\set failedRefundID 'd7450000-0000-0000-0000-000000000006'
\set finalClaimID 'd7450000-0000-0000-0000-000000000007'
\set finalCreditNoteID 'd7450000-0000-0000-0000-000000000008'
\set finalPriorClaimID 'd7450000-0000-0000-0000-000000000009'
\set finalPriorCreditNoteID 'd7450000-0000-0000-0000-000000000010'
\set finalPriorPurchaseID 'd7450000-0000-0000-0000-000000000011'
\set finalPriorRefundID 'd7450000-0000-0000-0000-000000000012'
\set finalPurchaseID 'd7450000-0000-0000-0000-000000000013'
\set finalRefundID 'd7450000-0000-0000-0000-000000000014'
\set groupCategoryID 'd7450000-0000-0000-0000-000000000015'
\set groupID 'd7450000-0000-0000-0000-000000000016'
\set issuedCreditNoteID 'd7450000-0000-0000-0000-000000000017'
\set issuedPurchaseID 'd7450000-0000-0000-0000-000000000018'
\set issuedRefundID 'd7450000-0000-0000-0000-000000000019'
\set recentClaimID 'd7450000-0000-0000-0000-000000000020'
\set recentCreditNoteID 'd7450000-0000-0000-0000-000000000021'
\set recentPurchaseID 'd7450000-0000-0000-0000-000000000022'
\set recentRefundID 'd7450000-0000-0000-0000-000000000023'
\set staleClaimID 'd7450000-0000-0000-0000-000000000024'
\set staleCreditNoteID 'd7450000-0000-0000-0000-000000000025'
\set stalePriorClaimID 'd7450000-0000-0000-0000-000000000026'
\set stalePriorCreditNoteID 'd7450000-0000-0000-0000-000000000027'
\set stalePriorPurchaseID 'd7450000-0000-0000-0000-000000000028'
\set stalePriorRefundID 'd7450000-0000-0000-0000-000000000029'
\set stalePurchaseID 'd7450000-0000-0000-0000-000000000030'
\set staleRefundID 'd7450000-0000-0000-0000-000000000031'
\set ticketTypeID 'd7450000-0000-0000-0000-000000000032'
\set userID 'd7450000-0000-0000-0000-000000000033'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the recovery fixtures
insert into community (
    banner_mobile_url, banner_url, community_id, description, display_name,
    logo_url, name
) values (
    'https://example.test/mobile.png', 'https://example.test/banner.png',
    :'communityID', 'Community', 'Community', 'https://example.test/logo.png',
    'stale-credit-note-community'
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

-- User owning the recovery purchases
insert into "user" (auth_hash, email, user_id, username)
values ('user', 'user@example.test', :'userID', 'user');

-- Event associated with the recovery purchases
insert into event (
    description, event_category_id, event_id, event_kind_id, group_id, name,
    payment_currency_code, slug, timezone
) values (
    'Event', :'eventCategoryID', :'eventID', 'in-person', :'groupID', 'Event',
    'USD', 'event', 'UTC'
);

-- Ticket type snapshotted by every recovery purchase
insert into event_ticket_type (
    event_id, event_ticket_type_id, "order", seats_total, title
) values (:'eventID', :'ticketTypeID', 1, 20, 'General admission');

-- Purchases providing immutable context for every recovery state
insert into event_purchase (
    amount_minor, charge_model, completed_at, connected_seller_id, currency_code,
    event_id, event_purchase_id, event_ticket_type_id,
    final_platform_fee_amount_minor, payment_provider_id,
    provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_invoice_id,
    provider_object_account_id, provider_payment_reference,
    provider_total_minor, provisional_platform_fee_amount_minor,
    seller_snapshot, status, subtotal_excluding_tax_minor, tax_amount_minor,
    tax_behavior, tax_calculation_mode, tax_classification, ticket_title,
    user_id, venue_snapshot
) values
    (2500, 'direct-charge', current_timestamp, 'acct_recovery', 'USD', :'eventID', :'failedPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_failed', 'ch_failed', 'cs_failed', 'in_failed', 'acct_recovery', 'pi_failed', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_recovery', 'USD', :'eventID', :'finalPriorPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_final_prior', 'ch_final_prior', 'cs_final_prior', 'in_final_prior', 'acct_recovery', 'pi_final_prior', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_recovery', 'USD', :'eventID', :'finalPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_final', 'ch_final', 'cs_final', 'in_final', 'acct_recovery', 'pi_final', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_recovery', 'USD', :'eventID', :'issuedPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_issued', 'ch_issued', 'cs_issued', 'in_issued', 'acct_recovery', 'pi_issued', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_recovery', 'USD', :'eventID', :'recentPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_recent', 'ch_recent', 'cs_recent', 'in_recent', 'acct_recovery', 'pi_recent', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_recovery', 'USD', :'eventID', :'stalePriorPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_stale_prior', 'ch_stale_prior', 'cs_stale_prior', 'in_stale_prior', 'acct_recovery', 'pi_stale_prior', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb),
    (2500, 'direct-charge', current_timestamp, 'acct_recovery', 'USD', :'eventID', :'stalePurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_stale', 'ch_stale', 'cs_stale', 'in_stale', 'acct_recovery', 'pi_stale', 2500, 100, '{"display_name":"Sponsor"}'::jsonb, 'refunded', 2300, 200, 'inclusive', 'manual', 'professional-event-admission', 'General admission', :'userID', '{}'::jsonb);

-- Successful refunds required by the credit-note fixtures
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    idempotency_key, kind, payment_provider_id, provider_refund_id,
    provider_refunded_at, status
) values
    (2500, 'USD', :'failedPurchaseID', :'failedRefundID', 'recover-refund-failed', 'automatic-unfulfillable-checkout', 'stripe', 're_failed', current_timestamp, 'provider-succeeded'),
    (2500, 'USD', :'finalPriorPurchaseID', :'finalPriorRefundID', 'recover-refund-final-prior', 'automatic-unfulfillable-checkout', 'stripe', 're_final_prior', current_timestamp, 'provider-succeeded'),
    (2500, 'USD', :'finalPurchaseID', :'finalRefundID', 'recover-refund-final', 'automatic-unfulfillable-checkout', 'stripe', 're_final', current_timestamp, 'provider-succeeded'),
    (2500, 'USD', :'issuedPurchaseID', :'issuedRefundID', 'recover-refund-issued', 'automatic-unfulfillable-checkout', 'stripe', 're_issued', current_timestamp, 'provider-succeeded'),
    (2500, 'USD', :'recentPurchaseID', :'recentRefundID', 'recover-refund-recent', 'automatic-unfulfillable-checkout', 'stripe', 're_recent', current_timestamp, 'provider-succeeded'),
    (2500, 'USD', :'stalePriorPurchaseID', :'stalePriorRefundID', 'recover-refund-stale-prior', 'automatic-unfulfillable-checkout', 'stripe', 're_stale_prior', current_timestamp, 'provider-succeeded'),
    (2500, 'USD', :'stalePurchaseID', :'staleRefundID', 'recover-refund-stale', 'automatic-unfulfillable-checkout', 'stripe', 're_stale', current_timestamp, 'provider-succeeded');

-- Credit notes covering recovery and protected states
insert into event_purchase_credit_note (
    event_purchase_credit_note_id, amount_minor, attempt_count, created_at,
    currency_code, event_purchase_refund_id, idempotency_key, next_attempt_at,
    payment_provider_id, provider_object_account_id, status, tax_amount_minor,
    updated_at,

    claim_id, claimed_at, completed_at, failure_message,
    provider_credit_note_id
) values
    (:'failedCreditNoteID', 2500, 2, '2024-01-01 00:00:00+00', 'USD', :'failedRefundID', 'recover-credit-failed', '2024-01-01 00:00:00+00', 'stripe', 'acct_recovery', 'failed', 200, '2024-01-01 00:00:00+00', null, null, null, 'retry later', null),
    (:'finalCreditNoteID', 2500, 10, '2024-01-01 00:00:00+00', 'USD', :'finalRefundID', 'recover-credit-final', '2024-01-01 00:00:00+00', 'stripe', 'acct_recovery', 'processing', 200, '2024-01-01 00:00:00+00', :'finalClaimID', current_timestamp - interval '16 minutes', null, null, null),
    (:'finalPriorCreditNoteID', 2500, 10, '2024-01-01 00:00:00+00', 'USD', :'finalPriorRefundID', 'recover-credit-final-prior', '2024-01-01 00:00:00+00', 'stripe', 'acct_recovery', 'processing', 200, '2024-01-01 00:00:00+00', :'finalPriorClaimID', current_timestamp - interval '16 minutes', null, 'provider timed out', null),
    (:'issuedCreditNoteID', 2500, 10, '2024-01-01 00:00:00+00', 'USD', :'issuedRefundID', 'recover-credit-issued', '2024-01-01 00:00:00+00', 'stripe', 'acct_recovery', 'issued', 200, '2024-01-01 00:00:00+00', null, null, '2024-01-02 00:00:00+00', null, 'cn_issued'),
    (:'recentCreditNoteID', 2500, 2, '2024-01-01 00:00:00+00', 'USD', :'recentRefundID', 'recover-credit-recent', '2024-01-01 00:00:00+00', 'stripe', 'acct_recovery', 'processing', 200, '2024-01-01 00:00:00+00', :'recentClaimID', current_timestamp - interval '14 minutes', null, null, null),
    (:'staleCreditNoteID', 2500, 2, '2024-01-01 00:00:00+00', 'USD', :'staleRefundID', 'recover-credit-stale', '2024-01-01 00:00:00+00', 'stripe', 'acct_recovery', 'processing', 200, '2024-01-01 00:00:00+00', :'staleClaimID', current_timestamp - interval '16 minutes', null, null, null),
    (:'stalePriorCreditNoteID', 2500, 3, '2024-01-01 00:00:00+00', 'USD', :'stalePriorRefundID', 'recover-credit-stale-prior', '2024-01-01 00:00:00+00', 'stripe', 'acct_recovery', 'processing', 200, '2024-01-01 00:00:00+00', :'stalePriorClaimID', current_timestamp - interval '16 minutes', null, 'provider unavailable', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should release every stale credit-note claim
select is(
    requeue_stale_event_purchase_credit_note_claims(),
    4,
    'Should release every stale credit-note claim'
);

-- Should leave non-processing and issued credit notes unchanged
select results_eq(
    format($$
        select event_purchase_credit_note_id, failure_message, status
        from event_purchase_credit_note
        where event_purchase_credit_note_id in (%L::uuid, %L::uuid)
        order by event_purchase_credit_note_id
    $$, :'failedCreditNoteID', :'issuedCreditNoteID'),
    format($$ values
        (%L::uuid, 'retry later'::text, 'failed'::text),
        (%L::uuid, null::text, 'issued'::text)
    $$, :'failedCreditNoteID', :'issuedCreditNoteID'),
    'Should leave non-processing and issued credit notes unchanged'
);

-- Should leave a recent processing claim unchanged
select results_eq(
    format($$
        select claim_id, claimed_at, failure_message, next_attempt_at, status,
            updated_at
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'recentCreditNoteID'),
    format($$ values (
        %L::uuid,
        current_timestamp - interval '14 minutes',
        null::text,
        '2024-01-01 00:00:00+00'::timestamptz,
        'processing'::text,
        '2024-01-01 00:00:00+00'::timestamptz
    ) $$, :'recentClaimID'),
    'Should leave a recent processing claim unchanged'
);

-- Should preserve an existing failure below the attempt limit
select results_eq(
    format($$
        select claim_id, claimed_at, failure_message,
            next_attempt_at = current_timestamp, status,
            updated_at = current_timestamp
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'stalePriorCreditNoteID'),
    $$ values (null::uuid, null::timestamptz, 'provider unavailable'::text, true, 'failed'::text, true) $$,
    'Should preserve an existing failure below the attempt limit'
);

-- Should preserve provider failure context on the final attempt
select results_eq(
    format($$
        select claim_id, claimed_at, failure_message, status,
            updated_at = current_timestamp
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'finalPriorCreditNoteID'),
    $$ values (
        null::uuid,
        null::timestamptz,
        E'provider timed out\nCredit-note worker claim expired after the final automatic attempt; provider outcome is unknown'::text,
        'failed'::text,
        true
    ) $$,
    'Should preserve provider failure context on the final attempt'
);

-- Should record final-attempt expiration when no provider failure exists
select results_eq(
    format($$
        select failure_message, next_attempt_at, status
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'finalCreditNoteID'),
    $$ values (
        'Credit-note worker claim expired after the final automatic attempt; provider outcome is unknown'::text,
        '2024-01-01 00:00:00+00'::timestamptz,
        'failed'::text
    ) $$,
    'Should record final-attempt expiration when no provider failure exists'
);

-- Should record worker expiration below the attempt limit
select results_eq(
    format($$
        select claim_id, claimed_at, failure_message,
            next_attempt_at = current_timestamp, status,
            updated_at = current_timestamp
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'staleCreditNoteID'),
    $$ values (
        null::uuid,
        null::timestamptz,
        'Credit-note worker claim expired'::text,
        true,
        'failed'::text,
        true
    ) $$,
    'Should record worker expiration below the attempt limit'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
