-- Tests attaching durable direct-charge invoice references.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd7310000-0000-0000-0000-000000000001'
\set eventCategoryID 'd7310000-0000-0000-0000-000000000002'
\set eventID 'd7310000-0000-0000-0000-000000000003'
\set groupCategoryID 'd7310000-0000-0000-0000-000000000004'
\set groupID 'd7310000-0000-0000-0000-000000000005'
\set purchaseID 'd7310000-0000-0000-0000-000000000006'
\set refundID 'd7310000-0000-0000-0000-000000000007'
\set ticketTypeID 'd7310000-0000-0000-0000-000000000008'
\set userID 'd7310000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the invoiced event
insert into community (
    banner_mobile_url, banner_url, community_id, description, display_name,
    logo_url, name
) values (
    'https://example.test/mobile.png', 'https://example.test/banner.png',
    :'communityID', 'Community', 'Community', 'https://example.test/logo.png',
    'attach-invoice-community'
);

-- Event category used by the invoiced event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the invoiced event group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the invoiced event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Attendee owning the direct-charge purchase
insert into "user" (auth_hash, email, user_id, username)
values ('user', 'user@example.test', :'userID', 'user');

-- Event associated with the direct-charge purchase
insert into event (
    description, event_category_id, event_id, event_kind_id, group_id, name,
    payment_currency_code, slug, timezone
) values (
    'Event', :'eventCategoryID', :'eventID', 'in-person', :'groupID', 'Event',
    'USD', 'event', 'UTC'
);

-- Ticket type snapshotted by the purchase
insert into event_ticket_type (
    event_id, event_ticket_type_id, "order", seats_total, title
) values (:'eventID', :'ticketTypeID', 1, 10, 'General admission');

-- Refunded direct-charge purchase awaiting its invoice event
insert into event_purchase (
    amount_minor, charge_model, completed_at, connected_seller_id, currency_code,
    event_id, event_purchase_id, event_ticket_type_id,
    final_platform_fee_amount_minor, payment_provider_id,
    provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_object_account_id,
    provider_payment_reference, provider_total_minor,
    provisional_platform_fee_amount_minor, seller_snapshot, status,
    subtotal_excluding_tax_minor, tax_amount_minor, tax_behavior,
    tax_calculation_mode, tax_classification, ticket_title, user_id,
    venue_snapshot
) values (
    2500, 'direct-charge', current_timestamp, 'acct_invoice', 'USD', :'eventID',
    :'purchaseID', :'ticketTypeID', 100, 'stripe', 'fee_invoice', 'ch_invoice',
    'cs_invoice', 'acct_invoice', 'pi_invoice', 2500, 100,
    '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded', 2300, 200,
    'inclusive', 'manual', 'professional-event-admission', 'General admission',
    :'userID', '{}'::jsonb
);

-- Successful provider refund that predates the invoice
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    idempotency_key, kind, payment_provider_id, provider_refund_id,
    provider_refunded_at, status
) values (
    2500, 'USD', :'purchaseID', :'refundID', 'refund-attach-invoice',
    'automatic-unfulfillable-checkout', 'stripe', 're_invoice', current_timestamp,
    'provider-succeeded'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject an invoice from a different connected account
select throws_ok(
    format(
        'select attach_invoice_to_event_purchase(%L, %L, %L, %L, null)',
        :'purchaseID', 'acct_wrong', 'in_invoice', 'https://invoice.test/one'
    ),
    'invoice account does not match the purchase seller',
    'Should reject an invoice from a different connected account'
);

-- Should attach a connected-account invoice after an earlier refund
select lives_ok(
    format(
        'select attach_invoice_to_event_purchase(%L, %L, %L, %L, %L)',
        :'purchaseID', 'acct_invoice', 'in_invoice',
        'https://invoice.test/one', 'https://invoice.test/one.pdf'
    ),
    'Should attach a connected-account invoice after an earlier refund'
);

-- Should persist the durable invoice identifier and current URLs
select results_eq(
    format($$
        select provider_invoice_id, provider_invoice_hosted_url,
            provider_invoice_pdf_url
        from event_purchase
        where event_purchase_id = %L::uuid
    $$, :'purchaseID'),
    $$ values (
        'in_invoice'::text,
        'https://invoice.test/one'::text,
        'https://invoice.test/one.pdf'::text
    ) $$,
    'Should persist the durable invoice identifier and current URLs'
);

-- Should queue a full credit note when the refund predates the invoice
select results_eq(
    format($$
        select amount_minor, currency_code, status, tax_amount_minor
        from event_purchase_credit_note
        where event_purchase_refund_id = %L::uuid
    $$, :'refundID'),
    $$ values (2500::bigint, 'USD'::text, 'pending'::text, 200::bigint) $$,
    'Should queue a full credit note when the refund predates the invoice'
);

-- Should refresh URLs idempotently for the same durable invoice
select lives_ok(
    format(
        'select attach_invoice_to_event_purchase(%L, %L, %L, %L, %L)',
        :'purchaseID', 'acct_invoice', 'in_invoice',
        'https://invoice.test/two', 'https://invoice.test/two.pdf'
    ),
    'Should refresh URLs idempotently for the same durable invoice'
);

-- Should reject replacement with a different invoice
select throws_ok(
    format(
        'select attach_invoice_to_event_purchase(%L, %L, %L, %L, null)',
        :'purchaseID', 'acct_invoice', 'in_other', 'https://invoice.test/other'
    ),
    'event purchase already has a different provider invoice',
    'Should reject replacement with a different invoice'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
