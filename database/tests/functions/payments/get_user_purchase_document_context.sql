-- Tests resolving attendee-owned provider document context.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd7390000-0000-0000-0000-000000000001'
\set creditNoteID 'd7390000-0000-0000-0000-000000000002'
\set eventCategoryID 'd7390000-0000-0000-0000-000000000003'
\set eventID 'd7390000-0000-0000-0000-000000000004'
\set groupCategoryID 'd7390000-0000-0000-0000-000000000005'
\set groupID 'd7390000-0000-0000-0000-000000000006'
\set otherUserID 'd7390000-0000-0000-0000-000000000007'
\set purchaseID 'd7390000-0000-0000-0000-000000000008'
\set refundID 'd7390000-0000-0000-0000-000000000009'
\set ticketTypeID 'd7390000-0000-0000-0000-000000000010'
\set userID 'd7390000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'otherUserID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event associated with the direct-charge purchase
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('payment_currency_code', 'USD'));

-- Ticket type snapshotted by the purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Refunded direct-charge purchase with a durable invoice
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
) values (
    2500, 'direct-charge', current_timestamp, 'acct_context', 'USD', :'eventID',
    :'purchaseID', :'ticketTypeID', 100, 'stripe', 'fee_context', 'ch_context',
    'cs_context', 'in_context', 'acct_context', 'pi_context', 2500, 100,
    '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded', 2300, 200,
    'inclusive', 'manual', 'professional-event-admission', 'General admission',
    :'userID', '{}'::jsonb
);

-- Successful provider refund linked to the purchase
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    idempotency_key, kind, payment_provider_id, provider_refund_id,
    provider_refunded_at, status
) values (
    2500, 'USD', :'purchaseID', :'refundID', 'refund-document-context',
    'automatic-unfulfillable-checkout', 'stripe', 're_context', current_timestamp,
    'provider-succeeded'
);

-- Issued credit note linked to the successful refund
insert into event_purchase_credit_note (
    amount_minor, completed_at, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, idempotency_key, payment_provider_id,
    provider_credit_note_id, provider_object_account_id, status, tax_amount_minor
) values (
    2500, current_timestamp, 'USD', :'creditNoteID', :'refundID',
    'document-context-credit-note', 'stripe', 'cn_context', 'acct_context',
    'issued', 200
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should resolve an attendee-owned invoice through its connected account
select results_eq(
    format($$
        select
            context->>'connected_seller_id',
            context->>'payment_provider',
            context->>'provider_document_id'
        from get_user_purchase_document_context(%L, %L, null) context
    $$, :'userID', :'purchaseID'),
    $$ values ('acct_context'::text, 'stripe'::text, 'in_context'::text) $$,
    'Should resolve an attendee-owned invoice through its connected account'
);

-- Should resolve an attendee-owned credit note through its connected account
select results_eq(
    format($$
        select
            context->>'connected_seller_id',
            context->>'payment_provider',
            context->>'provider_document_id'
        from get_user_purchase_document_context(%L, %L, %L) context
    $$, :'userID', :'purchaseID', :'creditNoteID'),
    $$ values ('acct_context'::text, 'stripe'::text, 'cn_context'::text) $$,
    'Should resolve an attendee-owned credit note through its connected account'
);

-- Should not expose an invoice to a different attendee
select is(
    get_user_purchase_document_context(:'otherUserID', :'purchaseID', null),
    null,
    'Should not expose an invoice to a different attendee'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
