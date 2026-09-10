-- Seeds schema-80 payment lifecycle shapes for the payment_job upgrade test.

begin;

\set communityID '81000000-0000-0000-0000-000000000001'
\set completedFeeID '81000000-0000-0000-0000-000000000061'
\set confirmedPurchaseID '81000000-0000-0000-0000-000000000030'
\set confirmedRefundID '81000000-0000-0000-0000-000000000031'
\set eventCategoryID '81000000-0000-0000-0000-000000000002'
\set eventID '81000000-0000-0000-0000-000000000005'
\set exhaustedCreditNoteID '81000000-0000-0000-0000-000000000051'
\set exhaustedPurchaseID '81000000-0000-0000-0000-000000000014'
\set exhaustedRefundID '81000000-0000-0000-0000-000000000015'
\set finalizedFailedPurchaseID '81000000-0000-0000-0000-000000000034'
\set finalizedFailedRefundID '81000000-0000-0000-0000-000000000035'
\set finalizedPurchaseID '81000000-0000-0000-0000-000000000018'
\set finalizedRefundID '81000000-0000-0000-0000-000000000019'
\set groupCategoryID '81000000-0000-0000-0000-000000000003'
\set groupID '81000000-0000-0000-0000-000000000004'
\set issuedCreditNoteID '81000000-0000-0000-0000-000000000050'
\set operatorID '81000000-0000-0000-0000-000000000008'
\set pendingCreditNoteID '81000000-0000-0000-0000-000000000052'
\set pendingFeeID '81000000-0000-0000-0000-000000000060'
\set pendingPurchaseID '81000000-0000-0000-0000-000000000010'
\set pendingRefundID '81000000-0000-0000-0000-000000000011'
\set processingClaimID '81000000-0000-0000-0000-000000000090'
\set processingCreditNoteClaimID '81000000-0000-0000-0000-000000000091'
\set processingCreditNoteID '81000000-0000-0000-0000-000000000053'
\set processingFeeClaimID '81000000-0000-0000-0000-000000000092'
\set processingFeeID '81000000-0000-0000-0000-000000000063'
\set processingPurchaseID '81000000-0000-0000-0000-000000000012'
\set processingRefundID '81000000-0000-0000-0000-000000000013'
\set recoveredFeeID '81000000-0000-0000-0000-000000000062'
\set recoveredPurchaseID '81000000-0000-0000-0000-000000000020'
\set recoveredRefundID '81000000-0000-0000-0000-000000000021'
\set terminalPurchaseID '81000000-0000-0000-0000-000000000016'
\set terminalRefundID '81000000-0000-0000-0000-000000000017'
\set ticketTypeID '81000000-0000-0000-0000-000000000006'
\set userID '81000000-0000-0000-0000-000000000007'

-- Community hosting the migration fixtures
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
    'Payment job upgrade fixtures',
    'Payment Job Community',
    'https://example.test/logo.png',
    'payment-job-community'
);

-- Event category of the refunded event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Payment job events');

-- Group category of the fixture group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Payment job groups');

-- Group owning the refunded event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Payment Job Group', 'payment-job-group');

-- Buyer of every purchase and the operator who recovered work
insert into "user" (auth_hash, email, email_verified, user_id, username)
values
    ('hash', 'payment-job-buyer@example.test', true, :'userID', 'payment-job-buyer'),
    ('hash', 'payment-job-operator@example.test', true, :'operatorID', 'payment-job-operator');

-- Ticketed event whose purchases entered refund workflows
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    20,
    'Refunded event',
    '2099-01-01 12:00:00+00',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Refunded Event',
    true,
    'refunded-event',
    '2099-01-01 10:00:00+00',
    'UTC'
);

-- Ticket tier snapshotted by every purchase
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'eventID', :'ticketTypeID', 1, 20, 'General admission');

-- Direct-charge purchases, one per lifecycle shape
insert into event_purchase (
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_application_fee_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_invoice_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    provisional_platform_fee_amount_minor,
    seller_snapshot,
    status,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
)
select
    2500,
    'direct-charge',
    'acct_payment_job',
    'USD',
    :'eventID',
    fixture.event_purchase_id,
    :'ticketTypeID',
    80,
    'stripe',
    'fee_' || fixture.reference,
    'ch_' || fixture.reference,
    'cs_' || fixture.reference,
    'in_' || fixture.reference,
    'acct_payment_job',
    'pi_' || fixture.reference,
    2500,
    100,
    '{"display_name":"Sponsor"}'::jsonb,
    fixture.status,
    2300,
    200,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'userID',
    '{}'::jsonb
from (values
    (:'confirmedPurchaseID'::uuid, 'refund-pending', 'confirmed'),
    (:'exhaustedPurchaseID'::uuid, 'refund-pending', 'exhausted'),
    (:'finalizedFailedPurchaseID'::uuid, 'refunded', 'finalized_failed'),
    (:'finalizedPurchaseID'::uuid, 'refunded', 'finalized'),
    (:'pendingPurchaseID'::uuid, 'refund-pending', 'pending'),
    (:'processingPurchaseID'::uuid, 'refund-pending', 'processing'),
    (:'recoveredPurchaseID'::uuid, 'refunded', 'recovered'),
    (:'terminalPurchaseID'::uuid, 'refund-pending', 'terminal')
) as fixture(event_purchase_id, status, reference);

-- Refunds covering every schema-80 lifecycle shape
insert into event_purchase_refund (
    amount_minor,
    attempt_count,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_provider_id,
    status,
    terminal_failure,

    claim_id,
    claimed_at,
    failure_message,
    finalized_at,
    provider_refund_id,
    provider_refunded_at,
    recovery_completed_at,
    recovery_completed_by_user_id,
    recovery_note,
    recovery_reference
) values
    -- Provider-confirmed refund that exhausted its attempts before finalization
    (2500, 10, 'USD', :'confirmedPurchaseID', :'confirmedRefundID', 'payment-job-refund-confirmed', 'event-cancellation', '2099-01-01 00:00:00+00', 'stripe', 'provider-succeeded', false, null, null, 'finalization failed', null, 're_confirmed', '2024-01-05 10:00:00+00', null, null, null, null),
    -- Retryable failure that used every automatic attempt
    (2500, 10, 'USD', :'exhaustedPurchaseID', :'exhaustedRefundID', 'payment-job-refund-exhausted', 'event-cancellation', '2024-01-03 10:00:00+00', 'stripe', 'provider-failed', false, null, null, 'provider unavailable', null, null, null, null, null, null, null),
    -- Locally finalized refund left in a non-terminal provider failure
    (2500, 2, 'USD', :'finalizedFailedPurchaseID', :'finalizedFailedRefundID', 'payment-job-refund-finalized-failed', 'automatic-unfulfillable-checkout', '2024-01-08 10:00:00+00', 'stripe', 'provider-failed', false, null, null, 'provider refund failed: re_finalized_failed', '2024-01-08 09:00:00+00', null, null, null, null, null, null),
    -- Finalized refund
    (2500, 1, 'USD', :'finalizedPurchaseID', :'finalizedRefundID', 'payment-job-refund-finalized', 'event-cancellation', '2024-01-04 10:00:00+00', 'stripe', 'finalized', false, null, null, null, '2024-01-04 11:00:00+00', 're_finalized', '2024-01-04 10:30:00+00', null, null, null, null),
    -- Refund still waiting for its first provider attempt
    (2500, 0, 'USD', :'pendingPurchaseID', :'pendingRefundID', 'payment-job-refund-pending', 'event-cancellation', '2024-01-01 10:00:00+00', 'stripe', 'provider-pending', false, null, null, null, null, null, null, null, null, null, null),
    -- Claimed refund whose provider success awaits finalization
    (2500, 3, 'USD', :'processingPurchaseID', :'processingRefundID', 'payment-job-refund-processing', 'event-cancellation', '2024-01-02 10:00:00+00', 'stripe', 'processing', false, :'processingClaimID', '2024-01-02 10:05:00+00', null, null, 're_processing', '2024-01-02 10:00:00+00', null, null, null, null),
    -- Terminal failure recovered by an operator after finalization
    (2500, 2, 'USD', :'recoveredPurchaseID', :'recoveredRefundID', 'payment-job-refund-recovered', 'event-cancellation', '2024-01-06 10:00:00+00', 'stripe', 'provider-failed', true, null, null, 'provider refund failed: re_recovered', '2024-01-06 11:00:00+00', 're_recovered', null, '2024-01-06 12:00:00+00', :'operatorID', 'Refunded by bank transfer', 'BANK-1'),
    -- Terminal failure awaiting operator recovery
    (2500, 2, 'USD', :'terminalPurchaseID', :'terminalRefundID', 'payment-job-refund-terminal', 'event-cancellation', '2024-01-07 10:00:00+00', 'stripe', 'provider-failed', true, null, null, 'provider refund failed: re_terminal', null, 're_terminal', null, null, null, null, null);

-- Credit notes covering issued, exhausted, pending and claimed work
insert into event_purchase_credit_note (
    amount_minor,
    attempt_count,
    currency_code,
    event_purchase_credit_note_id,
    event_purchase_refund_id,
    idempotency_key,
    next_attempt_at,
    payment_provider_id,
    provider_object_account_id,
    status,
    tax_amount_minor,

    claim_id,
    claimed_at,
    completed_at,
    failure_message,
    provider_credit_note_id
) values
    -- Issued document
    (2500, 1, 'USD', :'issuedCreditNoteID', :'finalizedRefundID', 'payment-job-credit-note-issued', '2024-01-04 11:00:00+00', 'stripe', 'acct_payment_job', 'issued', 200, null, null, '2024-01-04 11:30:00+00', null, 'cn_issued'),
    -- Exhausted document work
    (2500, 10, 'USD', :'exhaustedCreditNoteID', :'confirmedRefundID', 'payment-job-credit-note-exhausted', '2099-01-01 00:00:00+00', 'stripe', 'acct_payment_job', 'failed', 200, null, null, null, 'credit note unavailable', null),
    -- Document work waiting for its first attempt
    (2500, 0, 'USD', :'pendingCreditNoteID', :'processingRefundID', 'payment-job-credit-note-pending', '2024-01-02 10:00:00+00', 'stripe', 'acct_payment_job', 'pending', 200, null, null, null, null, null),
    -- Claimed document work
    (2500, 2, 'USD', :'processingCreditNoteID', :'recoveredRefundID', 'payment-job-credit-note-processing', '2024-01-06 10:00:00+00', 'stripe', 'acct_payment_job', 'processing', 200, :'processingCreditNoteClaimID', '2024-01-06 10:05:00+00', null, null, null);

-- Application-fee adjustments covering pending, completed, recovered and claimed work
insert into event_purchase_application_fee_adjustment (
    amount_minor,
    attempt_count,
    event_purchase_application_fee_adjustment_id,
    event_purchase_id,
    idempotency_key,
    kind,
    next_attempt_at,
    status,

    claim_id,
    claimed_at,
    completed_at,
    failure_message,
    provider_application_fee_refund_id,
    recovery_completed_at,
    recovery_completed_by_user_id,
    recovery_note,
    recovery_reference
) values
    -- Tax correction waiting for its first attempt
    (20, 0, :'pendingFeeID', :'pendingPurchaseID', 'payment-job-fee-pending', 'tax-reconciliation', '2024-01-01 10:00:00+00', 'pending', null, null, null, null, null, null, null, null, null),
    -- Completed fee refund
    (80, 1, :'completedFeeID', :'finalizedPurchaseID', 'payment-job-fee-completed', 'purchase-refund', '2024-01-04 11:00:00+00', 'completed', null, null, '2024-01-04 11:45:00+00', null, 'fr_completed', null, null, null, null),
    -- Fee refund recovered by an operator
    (80, 10, :'recoveredFeeID', :'recoveredPurchaseID', 'payment-job-fee-recovered', 'purchase-refund', '2099-01-01 00:00:00+00', 'completed', null, null, '2024-01-06 13:00:00+00', null, 'fr_recovered', '2024-01-06 13:00:00+00', :'operatorID', 'Fee returned manually', 'FEE-1'),
    -- Claimed fee refund
    (80, 4, :'processingFeeID', :'processingPurchaseID', 'payment-job-fee-processing', 'purchase-refund', '2024-01-02 10:00:00+00', 'processing', :'processingFeeClaimID', '2024-01-02 10:06:00+00', null, null, null, null, null, null, null);

commit;
