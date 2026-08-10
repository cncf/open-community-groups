-- Tests releasing failed credit-note claims.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set claimID 'd7360000-0000-0000-0000-000000000001'
\set communityID 'd7360000-0000-0000-0000-000000000002'
\set creditNoteID 'd7360000-0000-0000-0000-000000000003'
\set eventCategoryID 'd7360000-0000-0000-0000-000000000004'
\set eventID 'd7360000-0000-0000-0000-000000000005'
\set finalClaimID 'd7360000-0000-0000-0000-000000000013'
\set finalCreditNoteID 'd7360000-0000-0000-0000-000000000014'
\set finalPurchaseID 'd7360000-0000-0000-0000-000000000015'
\set finalRefundID 'd7360000-0000-0000-0000-000000000016'
\set groupCategoryID 'd7360000-0000-0000-0000-000000000006'
\set groupID 'd7360000-0000-0000-0000-000000000007'
\set purchaseID 'd7360000-0000-0000-0000-000000000008'
\set refundID 'd7360000-0000-0000-0000-000000000009'
\set ticketTypeID 'd7360000-0000-0000-0000-000000000010'
\set userID 'd7360000-0000-0000-0000-000000000011'
\set wrongClaimID 'd7360000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the credit-note event
insert into community (
    banner_mobile_url, banner_url, community_id, description, display_name,
    logo_url, name
) values (
    'https://example.test/mobile.png', 'https://example.test/banner.png',
    :'communityID', 'Community', 'Community', 'https://example.test/logo.png',
    'fail-credit-note-community'
);

-- Event category used by the credit-note event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the credit-note group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the credit-note event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Attendee owning both direct-charge purchases
insert into "user" (auth_hash, email, user_id, username)
values ('user', 'user@example.test', :'userID', 'user');

-- Event associated with both direct-charge purchases
insert into event (
    description, event_category_id, event_id, event_kind_id, group_id, name,
    payment_currency_code, slug, timezone
) values (
    'Event', :'eventCategoryID', :'eventID', 'in-person', :'groupID', 'Event',
    'USD', 'event', 'UTC'
);

-- Ticket type snapshotted by both purchases
insert into event_ticket_type (
    event_id, event_ticket_type_id, "order", seats_total, title
) values (:'eventID', :'ticketTypeID', 1, 10, 'General admission');

-- Refunded purchases owning retryable and final credit-note claims
insert into event_purchase (
    amount_minor, charge_model, connected_seller_id, currency_code, event_id,
    event_purchase_id, event_ticket_type_id, final_platform_fee_amount_minor,
    payment_provider_id, provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_invoice_id, provider_object_account_id,
    provider_payment_reference, provider_total_minor,
    provisional_platform_fee_amount_minor, seller_snapshot, status,
    subtotal_excluding_tax_minor, tax_amount_minor, tax_behavior,
    tax_calculation_mode, tax_classification, ticket_title, user_id,
    venue_snapshot
) values
    (
        2500, 'direct-charge', 'acct_credit', 'USD', :'eventID', :'purchaseID',
        :'ticketTypeID', 100, 'stripe', 'fee_credit', 'ch_credit', 'cs_credit',
        'in_credit', 'acct_credit', 'pi_credit', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'userID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_credit', 'USD', :'eventID',
        :'finalPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_credit_final',
        'ch_credit_final', 'cs_credit_final', 'in_credit_final', 'acct_credit',
        'pi_credit_final', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'userID', '{}'::jsonb
    );

-- Successful refunds owning retryable and final credit-note claims
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    idempotency_key, kind, payment_provider_id, provider_refund_id,
    provider_refunded_at, status
) values
    (
        2500, 'USD', :'purchaseID', :'refundID', 'refund-fail-credit-note',
        'automatic-unfulfillable-checkout', 'stripe', 're_credit',
        current_timestamp, 'provider-succeeded'
    ),
    (
        2500, 'USD', :'finalPurchaseID', :'finalRefundID',
        'refund-final-credit-note', 'automatic-unfulfillable-checkout',
        'stripe', 're_credit_final', current_timestamp, 'provider-succeeded'
    );

-- Retryable and final-attempt credit-note claims
insert into event_purchase_credit_note (
    amount_minor, attempt_count, claim_id, claimed_at, currency_code,
    event_purchase_credit_note_id, event_purchase_refund_id, idempotency_key,
    payment_provider_id, provider_object_account_id, status, tax_amount_minor
) values
    (
        2500, 1, :'claimID', current_timestamp, 'USD', :'creditNoteID',
        :'refundID', 'fail-credit-note', 'stripe', 'acct_credit',
        'processing', 200
    ),
    (
        2500, 10, :'finalClaimID', current_timestamp, 'USD',
        :'finalCreditNoteID', :'finalRefundID', 'fail-final-credit-note',
        'stripe', 'acct_credit', 'processing', 200
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a stale credit-note failure claim
select throws_ok(
    format(
        'select record_event_purchase_credit_note_failure(%L, %L, %L)',
        :'creditNoteID', :'wrongClaimID', 'wrong claim'
    ),
    'credit-note claim is stale',
    'Should reject a stale credit-note failure claim'
);

-- Should release a failed credit-note claim for retry
select lives_ok(
    format(
        'select record_event_purchase_credit_note_failure(%L, %L, %L)',
        :'creditNoteID', :'claimID', 'temporary provider failure'
    ),
    'Should release a failed credit-note claim for retry'
);

-- Should persist the retryable credit-note failure
select results_eq(
    format($$
        select attempt_count, claim_id, failure_message, status
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'creditNoteID'),
    $$ values (
        1, null::uuid, 'temporary provider failure'::text, 'failed'::text
    ) $$,
    'Should persist the retryable credit-note failure'
);

-- Should release the final automatic credit-note claim for recovery
select lives_ok(
    format(
        'select record_event_purchase_credit_note_failure(%L, %L, %L)',
        :'finalCreditNoteID', :'finalClaimID', 'final provider failure'
    ),
    'Should release the final automatic credit-note claim for recovery'
);

-- Should preserve the exhausted attempt count for operator recovery
select results_eq(
    format($$
        select attempt_count, claim_id, failure_message, status
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'finalCreditNoteID'),
    $$ values (
        10, null::uuid, 'final provider failure'::text, 'failed'::text
    ) $$,
    'Should preserve the exhausted attempt count for operator recovery'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
