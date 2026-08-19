-- Tests claiming durable credit-note creation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd7350000-0000-0000-0000-000000000001'
\set creditNoteID 'd7350000-0000-0000-0000-000000000002'
\set eventCategoryID 'd7350000-0000-0000-0000-000000000003'
\set eventID 'd7350000-0000-0000-0000-000000000004'
\set finalCreditNoteID 'd7350000-0000-0000-0000-000000000011'
\set finalPurchaseID 'd7350000-0000-0000-0000-000000000012'
\set finalRefundID 'd7350000-0000-0000-0000-000000000013'
\set groupCategoryID 'd7350000-0000-0000-0000-000000000005'
\set groupID 'd7350000-0000-0000-0000-000000000006'
\set purchaseID 'd7350000-0000-0000-0000-000000000007'
\set refundID 'd7350000-0000-0000-0000-000000000008'
\set retryCreditNoteID 'd7350000-0000-0000-0000-000000000014'
\set retryPurchaseID 'd7350000-0000-0000-0000-000000000015'
\set retryRefundID 'd7350000-0000-0000-0000-000000000016'
\set staleClaimID 'd7350000-0000-0000-0000-000000000017'
\set staleCreditNoteID 'd7350000-0000-0000-0000-000000000018'
\set stalePurchaseID 'd7350000-0000-0000-0000-000000000019'
\set staleRefundID 'd7350000-0000-0000-0000-000000000020'
\set ticketTypeID 'd7350000-0000-0000-0000-000000000009'
\set userID 'd7350000-0000-0000-0000-000000000010'

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
    'claim-credit-note-community'
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

-- Attendee owning the refunded purchases
insert into "user" (auth_hash, email, user_id, username)
values ('user', 'user@example.test', :'userID', 'user');

-- Event associated with the refunded purchases
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
    amount_minor, charge_model, completed_at, connected_seller_id, currency_code,
    event_id, event_purchase_id, event_ticket_type_id,
    final_platform_fee_amount_minor, payment_provider_id,
    provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_invoice_id, provider_object_account_id,
    provider_payment_reference, provider_total_minor,
    provisional_platform_fee_amount_minor, seller_snapshot, status,
    subtotal_excluding_tax_minor, tax_amount_minor, tax_behavior,
    tax_calculation_mode, tax_classification, ticket_title, user_id,
    venue_snapshot
) values
    (
        2500, 'direct-charge', current_timestamp, 'acct_credit', 'USD',
        :'eventID', :'purchaseID', :'ticketTypeID', 100, 'stripe', 'fee_credit',
        'ch_credit', 'cs_credit', 'in_credit', 'acct_credit', 'pi_credit',
        2500, 100, '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded',
        2300, 200, 'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'userID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', current_timestamp, 'acct_credit', 'USD',
        :'eventID', :'retryPurchaseID', :'ticketTypeID', 100, 'stripe',
        'fee_retry', 'ch_retry', 'cs_retry', 'in_retry', 'acct_credit',
        'pi_retry', 2500, 100, '{"display_name":"Fiscal Sponsor"}'::jsonb,
        'refunded', 2300, 200, 'inclusive', 'manual',
        'professional-event-admission', 'General admission', :'userID',
        '{}'::jsonb
    ),
    (
        2500, 'direct-charge', current_timestamp, 'acct_credit', 'USD',
        :'eventID', :'stalePurchaseID', :'ticketTypeID', 100, 'stripe',
        'fee_stale', 'ch_stale', 'cs_stale', 'in_stale', 'acct_credit',
        'pi_stale', 2500, 100, '{"display_name":"Fiscal Sponsor"}'::jsonb,
        'refunded', 2300, 200, 'inclusive', 'manual',
        'professional-event-admission', 'General admission', :'userID',
        '{}'::jsonb
    ),
    (
        2500, 'direct-charge', current_timestamp, 'acct_credit', 'USD',
        :'eventID', :'finalPurchaseID', :'ticketTypeID', 100, 'stripe',
        'fee_final', 'ch_final', 'cs_final', 'in_final', 'acct_credit',
        'pi_final', 2500, 100, '{"display_name":"Fiscal Sponsor"}'::jsonb,
        'refunded', 2300, 200, 'inclusive', 'manual',
        'professional-event-admission', 'General admission', :'userID',
        '{}'::jsonb
    );

-- Successful refunds required before credit-note work can be claimed
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    idempotency_key, kind, payment_provider_id, provider_refund_id,
    provider_refunded_at, status
) values
    (
        2500, 'USD', :'purchaseID', :'refundID', 'refund-claim-credit-note',
        'automatic-unfulfillable-checkout', 'stripe', 're_credit',
        current_timestamp, 'provider-succeeded'
    ),
    (
        2500, 'USD', :'retryPurchaseID', :'retryRefundID',
        'refund-claim-retry-credit-note', 'automatic-unfulfillable-checkout',
        'stripe', 're_retry', current_timestamp, 'provider-succeeded'
    ),
    (
        2500, 'USD', :'stalePurchaseID', :'staleRefundID',
        'refund-claim-stale-credit-note', 'automatic-unfulfillable-checkout',
        'stripe', 're_stale', current_timestamp, 'provider-succeeded'
    ),
    (
        2500, 'USD', :'finalPurchaseID', :'finalRefundID',
        'refund-claim-final-credit-note', 'automatic-unfulfillable-checkout',
        'stripe', 're_final', current_timestamp, 'provider-succeeded'
    );

-- Pending, retryable, stale, and exhausted claim fixtures
insert into event_purchase_credit_note (
    amount_minor, attempt_count, claim_id, claimed_at, created_at, currency_code,
    event_purchase_credit_note_id, event_purchase_refund_id, failure_message,
    idempotency_key, next_attempt_at, payment_provider_id,
    provider_object_account_id, status, tax_amount_minor
) values
    (
        2500, 0, null, null, '2024-01-01 00:00:00+00', 'USD', :'creditNoteID',
        :'refundID', null, 'claim-credit-note', '2024-01-01 00:00:00+00',
        'stripe', 'acct_credit', 'pending', 200
    ),
    (
        2500, 1, null, null, '2024-01-02 00:00:00+00', 'USD',
        :'retryCreditNoteID', :'retryRefundID', 'provider unavailable',
        'claim-retry-credit-note', '2024-01-02 00:00:00+00', 'stripe',
        'acct_credit', 'failed', 200
    ),
    (
        2500, 1, :'staleClaimID', current_timestamp - interval '16 minutes',
        '2024-01-03 00:00:00+00', 'USD', :'staleCreditNoteID', :'staleRefundID',
        null, 'claim-stale-credit-note', '2024-01-03 00:00:00+00', 'stripe',
        'acct_credit', 'processing', 200
    ),
    (
        2500, 10, gen_random_uuid(), current_timestamp - interval '16 minutes',
        '2024-01-04 00:00:00+00', 'USD', :'finalCreditNoteID', :'finalRefundID',
        'provider timed out', 'claim-final-credit-note',
        '2024-01-04 00:00:00+00', 'stripe',
        'acct_credit', 'processing', 200
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should claim the pending credit note with complete provider context
create temporary table first_claim as
select claim_event_purchase_credit_note('stripe') as item;
select results_eq(
    $$
        select
            item->>'amount_minor',
            (
                select attempt_count::text
                from event_purchase_credit_note
                where event_purchase_credit_note_id =
                    (item->>'event_purchase_credit_note_id')::uuid
            ),
            (item->>'claim_id') is not null,
            item->>'connected_seller_id',
            item->>'event_purchase_credit_note_id',
            item->>'event_purchase_id',
            item->>'event_purchase_refund_id',
            item->>'idempotency_key',
            item->>'provider_invoice_id',
            item->>'provider_refund_id',
            item->>'tax_amount_minor'
        from first_claim
    $$,
    format(
        $$ values (
            '2500'::text, '1'::text, true, 'acct_credit'::text,
            %L::text, %L::text, %L::text, 'claim-credit-note'::text,
            'in_credit'::text, 're_credit'::text, '200'::text
        ) $$,
        :'creditNoteID', :'purchaseID', :'refundID'
    ),
    'Should claim the pending credit note with complete provider context'
);

-- Should claim failed credit-note work as the next retry attempt
create temporary table retry_claim as
select claim_event_purchase_credit_note('stripe') as item;
select results_eq(
    $$
        select
            (
                select attempt_count::text
                from event_purchase_credit_note
                where event_purchase_credit_note_id =
                    (item->>'event_purchase_credit_note_id')::uuid
            ),
            item->>'event_purchase_credit_note_id'
        from retry_claim
    $$,
    format($$ values ('2'::text, %L::text) $$, :'retryCreditNoteID'),
    'Should claim failed credit-note work as the next retry attempt'
);

-- Should reclaim an abandoned credit-note claim below the attempt limit
create temporary table stale_claim as
select claim_event_purchase_credit_note('stripe') as item;
select results_eq(
    $$
        select
            (
                select attempt_count::text
                from event_purchase_credit_note
                where event_purchase_credit_note_id =
                    (item->>'event_purchase_credit_note_id')::uuid
            ),
            item->>'event_purchase_credit_note_id'
        from stale_claim
    $$,
    format($$ values ('2'::text, %L::text) $$, :'staleCreditNoteID'),
    'Should reclaim an abandoned credit-note claim below the attempt limit'
);

-- Should not reclaim an abandoned final automatic attempt
select is(
    claim_event_purchase_credit_note('stripe'),
    null,
    'Should not reclaim an abandoned final automatic attempt'
);

-- Should surface an abandoned final credit-note attempt for operator action
select results_eq(
    format($$
        select attempt_count, claim_id, failure_message, status
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'finalCreditNoteID'),
    $$ values (
        10,
        null::uuid,
        E'provider timed out\nCredit-note worker claim expired after the final automatic attempt; provider outcome is unknown'::text,
        'failed'::text
    ) $$,
    'Should surface an abandoned final credit-note attempt for operator action'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
