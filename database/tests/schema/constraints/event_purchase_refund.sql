-- Tests event purchase refund constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendanceLinkedJobID 'c0e10000-0000-0000-0000-000000000001'
\set attendanceLinkedPurchaseID 'c0e10000-0000-0000-0000-000000000002'
\set attendanceRefundRequestID 'c0e10000-0000-0000-0000-000000000003'
\set attendanceUnlinkedJobID 'c0e10000-0000-0000-0000-000000000004'
\set attendanceUnlinkedPurchaseID 'c0e10000-0000-0000-0000-000000000005'
\set buyerID 'c0e10000-0000-0000-0000-000000000006'
\set communityID 'c0e10000-0000-0000-0000-000000000007'
\set eventCategoryID 'c0e10000-0000-0000-0000-000000000008'
\set eventID 'c0e10000-0000-0000-0000-000000000009'
\set finalizedJobID 'c0e10000-0000-0000-0000-00000000000a'
\set finalizedPurchaseID 'c0e10000-0000-0000-0000-00000000000b'
\set finalizedWithoutTimeJobID 'c0e10000-0000-0000-0000-000000000012'
\set finalizedWithoutTimePurchaseID 'c0e10000-0000-0000-0000-000000000013'
\set groupCategoryID 'c0e10000-0000-0000-0000-00000000000c'
\set groupID 'c0e10000-0000-0000-0000-00000000000d'
\set organizerID 'c0e10000-0000-0000-0000-00000000000e'
\set pendingFinalizedJobID 'c0e10000-0000-0000-0000-00000000000f'
\set pendingFinalizedPurchaseID 'c0e10000-0000-0000-0000-000000000010'
\set providerFailedFinalizedJobID 'c0e10000-0000-0000-0000-000000000014'
\set providerFailedFinalizedPurchaseID 'c0e10000-0000-0000-0000-000000000015'
\set ticketTypeID 'c0e10000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Buyer of the refunded purchases
select fx_user(:'buyerID');

-- Organizer cancelling attendance
select fx_user(:'organizerID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event selling the refunded tickets
select fx_event(:'eventID', :'groupID', :'eventCategoryID', '{"payment_currency_code": "USD"}');

-- Ticket type of the refunded purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', '{"title": "General admission"}');

-- Paid direct-charge purchases backing one refund scenario each
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    connected_seller_id,
    currency_code,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    seller_snapshot,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
)
select
    purchase.event_purchase_id::uuid,
    2500,
    'direct-charge',
    :'eventID',
    :'ticketTypeID',
    'refund-pending',
    'General admission',
    :'buyerID',

    'acct_c0e10000',
    'USD',
    0,
    'stripe',
    'ch_' || purchase.event_purchase_id,
    'cs_' || purchase.event_purchase_id,
    'acct_c0e10000',
    'pi_' || purchase.event_purchase_id,
    2500,
    '{"connected_account_id": "acct_c0e10000", "display_name": "Refund Seller", "provider": "stripe"}'::jsonb,
    2500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
from (values
    (:'attendanceLinkedPurchaseID'),
    (:'attendanceUnlinkedPurchaseID'),
    (:'finalizedPurchaseID'),
    (:'finalizedWithoutTimePurchaseID'),
    (:'pendingFinalizedPurchaseID'),
    (:'providerFailedFinalizedPurchaseID')
) as purchase (event_purchase_id);

-- Organizer-approved attendance cancellation request
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status,

    requested_reason,
    reviewed_at,
    reviewed_by_user_id
) values (
    :'attendanceRefundRequestID',
    :'attendanceLinkedPurchaseID',
    :'organizerID',
    'approving',

    'Attendance cancellation requested by an organizer',
    current_timestamp,
    :'organizerID'
);

-- Pending refund jobs backing one refund scenario each
insert into payment_job (
    payment_job_id,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status
) values
    (:'attendanceLinkedJobID', :'attendanceLinkedPurchaseID', 'c0e10000-attendance-linked', 'event-purchase-refund', 'stripe', 'pending'),
    (:'attendanceUnlinkedJobID', :'attendanceUnlinkedPurchaseID', 'c0e10000-attendance-unlinked', 'event-purchase-refund', 'stripe', 'pending'),
    (:'finalizedJobID', :'finalizedPurchaseID', 'c0e10000-finalized', 'event-purchase-refund', 'stripe', 'pending'),
    (:'finalizedWithoutTimeJobID', :'finalizedWithoutTimePurchaseID', 'c0e10000-finalized-without-time', 'event-purchase-refund', 'stripe', 'pending'),
    (:'pendingFinalizedJobID', :'pendingFinalizedPurchaseID', 'c0e10000-pending-finalized', 'event-purchase-refund', 'stripe', 'pending'),
    (:'providerFailedFinalizedJobID', :'providerFailedFinalizedPurchaseID', 'c0e10000-provider-failed-finalized', 'event-purchase-refund', 'stripe', 'pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept attendance cancellation refunds linked to a refund request
select lives_ok(
    format(
        $$
            insert into event_purchase_refund (
                amount_minor,
                currency_code,
                event_purchase_id,
                kind,
                payment_job_id,
                payment_provider_id,
                status,

                event_refund_request_id
            ) values (
                2500,
                'USD',
                %L::uuid,
                'attendance-cancellation',
                %L::uuid,
                'stripe',
                'provider-pending',

                %L::uuid
            )
        $$,
        :'attendanceLinkedPurchaseID',
        :'attendanceLinkedJobID',
        :'attendanceRefundRequestID'
    ),
    'Should accept attendance cancellation refunds linked to a refund request'
);

-- Should accept finalized refunds with a finalization time
select lives_ok(
    format(
        $$
            insert into event_purchase_refund (
                amount_minor,
                currency_code,
                event_purchase_id,
                kind,
                payment_job_id,
                payment_provider_id,
                status,

                finalized_at,
                provider_refund_id
            ) values (
                2500,
                'USD',
                %L::uuid,
                'event-cancellation',
                %L::uuid,
                'stripe',
                'finalized',

                current_timestamp,
                're_c0e10000_finalized'
            )
        $$,
        :'finalizedPurchaseID',
        :'finalizedJobID'
    ),
    'Should accept finalized refunds with a finalization time'
);

-- Should accept terminal provider failures that keep their finalization time
select lives_ok(
    format(
        $$
            insert into event_purchase_refund (
                amount_minor,
                currency_code,
                event_purchase_id,
                kind,
                payment_job_id,
                payment_provider_id,
                status,
                terminal_failure,

                finalized_at,
                provider_refund_id
            ) values (
                2500,
                'USD',
                %L::uuid,
                'event-cancellation',
                %L::uuid,
                'stripe',
                'provider-failed',
                true,

                current_timestamp,
                're_c0e10000_provider_failed_finalized'
            )
        $$,
        :'providerFailedFinalizedPurchaseID',
        :'providerFailedFinalizedJobID'
    ),
    'Should accept terminal provider failures that keep their finalization time'
);

-- Should reject attendance cancellation refunds without a refund request
select throws_ok(
    format(
        $$
            insert into event_purchase_refund (
                amount_minor,
                currency_code,
                event_purchase_id,
                kind,
                payment_job_id,
                payment_provider_id,
                status
            ) values (
                2500,
                'USD',
                %L::uuid,
                'attendance-cancellation',
                %L::uuid,
                'stripe',
                'provider-pending'
            )
        $$,
        :'attendanceUnlinkedPurchaseID',
        :'attendanceUnlinkedJobID'
    ),
    '23514',
    'new row for relation "event_purchase_refund" violates check constraint "event_purchase_refund_kind_request_chk"',
    'Should reject attendance cancellation refunds without a refund request'
);

-- Should reject finalized refunds without a finalization time
select throws_ok(
    format(
        $$
            insert into event_purchase_refund (
                amount_minor,
                currency_code,
                event_purchase_id,
                kind,
                payment_job_id,
                payment_provider_id,
                status,

                provider_refund_id
            ) values (
                2500,
                'USD',
                %L::uuid,
                'event-cancellation',
                %L::uuid,
                'stripe',
                'finalized',

                're_c0e10000_finalized_without_time'
            )
        $$,
        :'finalizedWithoutTimePurchaseID',
        :'finalizedWithoutTimeJobID'
    ),
    '23514',
    'new row for relation "event_purchase_refund" violates check constraint "event_purchase_refund_finalized_at_status_chk"',
    'Should reject finalized refunds without a finalization time'
);

-- Should reject provider-pending refunds with a finalization time
select throws_ok(
    format(
        $$
            insert into event_purchase_refund (
                amount_minor,
                currency_code,
                event_purchase_id,
                kind,
                payment_job_id,
                payment_provider_id,
                status,

                finalized_at
            ) values (
                2500,
                'USD',
                %L::uuid,
                'event-cancellation',
                %L::uuid,
                'stripe',
                'provider-pending',

                current_timestamp
            )
        $$,
        :'pendingFinalizedPurchaseID',
        :'pendingFinalizedJobID'
    ),
    '23514',
    'new row for relation "event_purchase_refund" violates check constraint "event_purchase_refund_finalized_at_status_chk"',
    'Should reject provider-pending refunds with a finalization time'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
