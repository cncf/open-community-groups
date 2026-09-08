-- Tests listing attendee-owned invoices and credit notes.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd7380000-0000-0000-0000-000000000001'
\set creditNoteID 'd7380000-0000-0000-0000-000000000002'
\set eventCategoryID 'd7380000-0000-0000-0000-000000000003'
\set eventID 'd7380000-0000-0000-0000-000000000004'
\set externalCompletedPurchaseID 'd7380000-0000-0000-0000-000000000011'
\set externalRefundedPurchaseID 'd7380000-0000-0000-0000-000000000012'
\set externalUserID 'd7380000-0000-0000-0000-000000000013'
\set groupCategoryID 'd7380000-0000-0000-0000-000000000005'
\set groupID 'd7380000-0000-0000-0000-000000000006'
\set purchaseID 'd7380000-0000-0000-0000-000000000007'
\set refundID 'd7380000-0000-0000-0000-000000000008'
\set ticketTypeID 'd7380000-0000-0000-0000-000000000009'
\set userID 'd7380000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the attendee document fixtures
insert into community (
    banner_mobile_url, banner_url, community_id, description, display_name,
    logo_url, name
) values (
    'https://example.test/mobile.png', 'https://example.test/banner.png',
    :'communityID', 'Community', 'Community', 'https://example.test/logo.png',
    'list-purchase-documents-community'
);

-- Event category used by the document event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the document group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the document event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Attendee owning the direct-charge purchase documents
insert into "user" (auth_hash, email, user_id, username)
values ('user', 'user@example.test', :'userID', 'user');

-- Attendee owning external completed and refunded purchases
insert into "user" (auth_hash, email, user_id, username)
values ('external-user', 'external@example.test', :'externalUserID', 'external-user');

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

-- Refunded direct-charge purchase with a durable invoice
insert into event_purchase (
    amount_minor, charge_model, completed_at, connected_seller_id, currency_code,
    event_id, event_purchase_id, event_ticket_type_id,
    final_platform_fee_amount_minor, payment_provider_id,
    provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_invoice_hosted_url,
    provider_invoice_id, provider_invoice_pdf_url, provider_object_account_id,
    provider_payment_reference, provider_total_minor,
    provisional_platform_fee_amount_minor, seller_snapshot, status,
    subtotal_excluding_tax_minor, tax_amount_minor, tax_behavior,
    tax_calculation_mode, tax_classification, ticket_title, user_id,
    venue_snapshot
) values (
    2500, 'direct-charge', current_timestamp, 'acct_documents', 'USD', :'eventID',
    :'purchaseID', :'ticketTypeID', 100, 'stripe', 'fee_documents',
    'ch_documents', 'cs_documents', 'https://invoice.test/one', 'in_documents',
    'https://invoice.test/one.pdf', 'acct_documents', 'pi_documents', 2500, 100,
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
    2500, 'USD', :'purchaseID', :'refundID', 'refund-list-documents',
    'automatic-unfulfillable-checkout', 'stripe', 're_documents',
    current_timestamp, 'provider-succeeded'
);

-- Issued credit note linked to the successful refund
insert into event_purchase_credit_note (
    amount_minor, completed_at, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, idempotency_key, payment_provider_id,
    provider_credit_note_id, provider_hosted_url, provider_object_account_id,
    provider_pdf_url, status, tax_amount_minor
) values (
    2500, current_timestamp, 'USD', :'creditNoteID', :'refundID',
    'list-documents-credit-note', 'stripe', 'cn_documents',
    'https://credit.test/one', 'acct_documents',
    'https://credit.test/one.pdf', 'issued', 200
);

-- Completed external purchase listed without provider invoice links
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    external_payment_details,
    external_payment_marked_by_user_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    4000,
    'external',
    '2026-01-02 12:00:00+00',
    'USD',
    :'eventID',
    :'externalCompletedPurchaseID',
    :'ticketTypeID',
    'Paid by bank transfer',
    :'userID',
    0,
    0,
    'completed',
    'General admission',
    :'externalUserID'
);

-- Refunded external purchase listed without invoice or credit-note links
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    external_payment_details,
    external_payment_marked_by_user_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    4000,
    'external',
    '2026-01-01 12:00:00+00',
    'USD',
    :'eventID',
    :'externalRefundedPurchaseID',
    :'ticketTypeID',
    'Paid by bank transfer',
    :'userID',
    0,
    0,
    'refunded',
    'General admission',
    :'externalUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list completed and refunded external purchases as externally managed
select results_eq(
    format($$
        select
            item->>'event_purchase_id',
            item->>'status',
            (item->>'externally_managed')::boolean,
            json_array_length(item->'credit_notes')
        from json_array_elements(
            list_user_purchase_documents(
                %L::uuid,
                '{"limit":20,"offset":0}'::jsonb
            )->'purchases'
        ) item
        order by item->>'event_purchase_id'
    $$, :'externalUserID'),
    format(
        $$ values
            (%L::text, 'completed'::text, true, 0),
            (%L::text, 'refunded'::text, true, 0)
        $$,
        :'externalCompletedPurchaseID',
        :'externalRefundedPurchaseID'
    ),
    'Should list completed and refunded external purchases as externally managed'
);

-- Should list the authenticated attendee direct-charge purchase
select is(
    (list_user_purchase_documents(
        :'userID', '{"limit":20,"offset":0}'::jsonb
    )->>'total')::int,
    1,
    'Should list the authenticated attendee direct-charge purchase'
);

-- Should omit invoice and seller fields from external purchase documents
select ok(
    not (purchase ?| array[
        'provider_invoice_id',
        'seller_display_name'
    ]),
    'Should omit invoice and seller fields from external purchase documents'
)
from (
    select (
        list_user_purchase_documents(
            :'externalUserID', '{"limit":20,"offset":0}'::jsonb
        )->'purchases'->0
    )::jsonb as purchase
) documents;

-- Should omit provider snapshots and unused display fields from the response
select ok(
    not (purchase ?| array[
        'community_display_name',
        'event_id',
        'provider_invoice_hosted_url',
        'provider_invoice_pdf_url',
        'refunded_at',
        'tax_amount_minor'
    ])
    and not (purchase->'credit_notes'->0 ?| array[
        'amount_minor',
        'provider_hosted_url',
        'provider_pdf_url',
        'tax_amount_minor'
    ]),
    'Should omit provider snapshots and unused display fields from the response'
)
from (
    select (
        list_user_purchase_documents(
            :'userID', '{"limit":20,"offset":0}'::jsonb
        )->'purchases'->0
    )::jsonb as purchase
) documents;

-- Should paginate purchase documents while retaining their total
select is(
    json_array_length(
        list_user_purchase_documents(
            :'userID', '{"limit":1,"offset":1}'::jsonb
        )->'purchases'
    ),
    0,
    'Should paginate purchase documents while retaining their total'
);

-- Should return the attendee invoice and linked issued credit note
select results_eq(
    format($$
        select
            item->>'provider_invoice_id',
            item->>'seller_display_name',
            item->'credit_notes'->0->>'provider_credit_note_id',
            item->'credit_notes'->0->>'status'
        from json_array_elements(
            list_user_purchase_documents(
                %L::uuid,
                '{"limit":20,"offset":0}'::jsonb
            )->'purchases'
        ) item
    $$, :'userID'),
    $$ values (
        'in_documents'::text,
        'Fiscal Sponsor'::text,
        'cn_documents'::text,
        'issued'::text
    ) $$,
    'Should return the attendee invoice and linked issued credit note'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
