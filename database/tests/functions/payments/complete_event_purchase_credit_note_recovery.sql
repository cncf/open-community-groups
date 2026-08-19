-- Tests externally completing exhausted credit notes.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'd7430000-0000-0000-0000-000000000001'
\set buyerID 'd7430000-0000-0000-0000-000000000002'
\set communityID 'd7430000-0000-0000-0000-000000000003'
\set creditNoteID 'd7430000-0000-0000-0000-000000000004'
\set eventCategoryID 'd7430000-0000-0000-0000-000000000005'
\set eventID 'd7430000-0000-0000-0000-000000000006'
\set groupCategoryID 'd7430000-0000-0000-0000-000000000007'
\set groupID 'd7430000-0000-0000-0000-000000000008'
\set lowCreditNoteID 'd7430000-0000-0000-0000-000000000012'
\set lowPurchaseID 'd7430000-0000-0000-0000-000000000013'
\set lowRefundID 'd7430000-0000-0000-0000-000000000014'
\set missingCreditNoteID 'd7430000-0000-0000-0000-000000000015'
\set missingGroupID 'd7430000-0000-0000-0000-000000000016'
\set pendingCreditNoteID 'd7430000-0000-0000-0000-000000000017'
\set pendingPurchaseID 'd7430000-0000-0000-0000-000000000018'
\set pendingRefundID 'd7430000-0000-0000-0000-000000000019'
\set purchaseID 'd7430000-0000-0000-0000-000000000009'
\set refundID 'd7430000-0000-0000-0000-000000000010'
\set ticketTypeID 'd7430000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the recovery event
insert into community (
    banner_mobile_url, banner_url, community_id, description, display_name,
    logo_url, name
) values (
    'https://example.test/mobile.png', 'https://example.test/banner.png',
    :'communityID', 'Community', 'Community', 'https://example.test/logo.png',
    'recover-credit-note-community'
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

-- Event manager and attendee used by authorization scenarios
insert into "user" (auth_hash, email, user_id, username) values
    ('actor', 'actor@example.test', :'actorID', 'actor'),
    ('buyer', 'buyer@example.test', :'buyerID', 'buyer');

-- Events-manager membership granting recovery authority
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'events-manager', :'actorID');

-- Event associated with each refunded purchase
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

-- Refunded purchases owning recoverable and ineligible credit notes
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
        'General admission', :'buyerID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_credit', 'USD', :'eventID',
        :'lowPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_low', 'ch_low',
        'cs_low', 'in_low', 'acct_credit', 'pi_low', 2500, 100,
        '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded', 2300, 200,
        'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'buyerID', '{}'::jsonb
    ),
    (
        2500, 'direct-charge', 'acct_credit', 'USD', :'eventID',
        :'pendingPurchaseID', :'ticketTypeID', 100, 'stripe', 'fee_pending',
        'ch_pending', 'cs_pending', 'in_pending', 'acct_credit', 'pi_pending',
        2500, 100, '{"display_name":"Fiscal Sponsor"}'::jsonb, 'refunded',
        2300, 200, 'inclusive', 'manual', 'professional-event-admission',
        'General admission', :'buyerID', '{}'::jsonb
    );

-- Successful refunds owning recoverable and ineligible credit notes
insert into event_purchase_refund (
    amount_minor, currency_code, event_purchase_id, event_purchase_refund_id,
    idempotency_key, kind, payment_provider_id, provider_refund_id,
    provider_refunded_at, status
) values
    (
        2500, 'USD', :'purchaseID', :'refundID', 'refund-recover-credit-note',
        'automatic-unfulfillable-checkout', 'stripe', 're_credit',
        current_timestamp, 'provider-succeeded'
    ),
    (
        2500, 'USD', :'lowPurchaseID', :'lowRefundID',
        'refund-recover-low-credit-note', 'automatic-unfulfillable-checkout',
        'stripe', 're_low', current_timestamp, 'provider-succeeded'
    ),
    (
        2500, 'USD', :'pendingPurchaseID', :'pendingRefundID',
        'refund-recover-pending-credit-note',
        'automatic-unfulfillable-checkout', 'stripe', 're_pending',
        current_timestamp, 'provider-succeeded'
    );

-- Exhausted, under-budget, and wrong-status credit notes
insert into event_purchase_credit_note (
    amount_minor, attempt_count, currency_code, event_purchase_credit_note_id,
    event_purchase_refund_id, failure_message, idempotency_key,
    payment_provider_id, provider_object_account_id, status, tax_amount_minor
) values
    (
        2500, 10, 'USD', :'creditNoteID', :'refundID',
        'automatic attempts exhausted', 'recover-credit-note', 'stripe',
        'acct_credit', 'failed', 200
    ),
    (
        2500, 9, 'USD', :'lowCreditNoteID', :'lowRefundID',
        'provider unavailable', 'recover-low-credit-note', 'stripe',
        'acct_credit', 'failed', 200
    ),
    (
        2500, 10, 'USD', :'pendingCreditNoteID', :'pendingRefundID', null,
        'recover-pending-credit-note', 'stripe', 'acct_credit', 'pending', 200
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject partial credit-note recovery evidence
select throws_ok(
    format($$
        update event_purchase_credit_note
        set recovery_reference = 'case-partial'
        where event_purchase_credit_note_id = %L::uuid
    $$, :'creditNoteID'),
    '23514',
    null,
    'Should reject partial credit-note recovery evidence'
);

-- Should require an actor user id
select throws_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(null, %L, %L, %L, %L, %L)',
        :'groupID', :'creditNoteID', 'cn_external', 'case-456',
        'Verified Stripe activity'
    ),
    'actor user id is required',
    'Should require an actor user id'
);

-- Should require a group id
select throws_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(%L, null, %L, %L, %L, %L)',
        :'actorID', :'creditNoteID', 'cn_external', 'case-456',
        'Verified Stripe activity'
    ),
    'group id is required',
    'Should require a group id'
);

-- Should require a provider credit-note id
select throws_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'creditNoteID', '   ', 'case-456',
        'Verified Stripe activity'
    ),
    'provider credit-note id is required',
    'Should require a provider credit-note id'
);

-- Should require a recovery reference
select throws_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'creditNoteID', 'cn_external', '   ',
        'Verified Stripe activity'
    ),
    'recovery reference is required',
    'Should require a recovery reference'
);

-- Should require a recovery note
select throws_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'creditNoteID', 'cn_external', 'case-456',
        '   '
    ),
    'recovery note is required',
    'Should require a recovery note'
);

-- Should reject a missing credit note
select throws_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'missingCreditNoteID', 'cn_external',
        'case-456', 'Verified Stripe activity'
    ),
    'recoverable credit note not found',
    'Should reject a missing credit note'
);

-- Should reject a credit note from another group
select throws_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'missingGroupID', :'creditNoteID', 'cn_external',
        'case-456', 'Verified Stripe activity'
    ),
    'recoverable credit note not found',
    'Should reject a credit note from another group'
);

-- Should require events write access at execution time
select throws_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(%L, %L, %L, %L, %L, %L)',
        :'buyerID', :'groupID', :'creditNoteID', 'cn_external', 'case-456',
        'Verified Stripe activity'
    ),
    'events write access is required',
    'Should require events write access at execution time'
);

-- Should reject credit-note work before automatic attempts are exhausted
select throws_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'lowCreditNoteID', 'cn_external', 'case-456',
        'Verified Stripe activity'
    ),
    'recoverable credit note not found',
    'Should reject credit-note work before automatic attempts are exhausted'
);

-- Should reject credit-note work with a non-failed status
select throws_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'pendingCreditNoteID', 'cn_external',
        'case-456', 'Verified Stripe activity'
    ),
    'recoverable credit note not found',
    'Should reject credit-note work with a non-failed status'
);

-- Should complete a credit note issued in Stripe
select lives_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'creditNoteID', 'cn_external', 'case-456',
        'Verified Stripe activity'
    ),
    'Should complete a credit note issued in Stripe'
);

-- Should store the provider credit note and recovery evidence
select results_eq(
    format($$
        select
            attempt_count,
            failure_message,
            provider_credit_note_id,
            recovery_completed_at is not null,
            recovery_completed_by_user_id,
            recovery_note,
            recovery_reference,
            status
        from event_purchase_credit_note
        where event_purchase_credit_note_id = %L::uuid
    $$, :'creditNoteID'),
    format(
        $$ values (
            10, null::text, %L::text, true, %L::uuid, %L::text, %L::text,
            'issued'::text
        ) $$,
        'cn_external', :'actorID', 'Verified Stripe activity', 'case-456'
    ),
    'Should store the provider credit note and recovery evidence'
);

-- Should audit the credit-note recovery evidence
select results_eq(
    $$ select action, details->>'recovery_reference' from audit_log $$,
    $$ values (
        'event_credit_note_recovery_completed'::text,
        'case-456'::text
    ) $$,
    'Should audit the credit-note recovery evidence'
);

-- Should accept an exact credit-note recovery completion replay
select lives_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'creditNoteID', 'cn_external', 'case-456',
        'Verified Stripe activity'
    ),
    'Should accept an exact credit-note recovery completion replay'
);

-- Should reject conflicting credit-note recovery evidence
select throws_ok(
    format(
        'select complete_event_purchase_credit_note_recovery(%L, %L, %L, %L, %L, %L)',
        :'actorID', :'groupID', :'creditNoteID', 'cn_other', 'case-456',
        'Verified Stripe activity'
    ),
    'credit-note recovery already completed with different evidence',
    'Should reject conflicting credit-note recovery evidence'
);

-- Should preserve every rejected credit-note work item
select results_eq(
    format($$
        select event_purchase_credit_note_id, attempt_count, status
        from event_purchase_credit_note
        where event_purchase_credit_note_id in (%L::uuid, %L::uuid)
        order by event_purchase_credit_note_id
    $$, :'lowCreditNoteID', :'pendingCreditNoteID'),
    format(
        $$ values
            (%L::uuid, 9, 'failed'::text),
            (%L::uuid, 10, 'pending'::text)
        $$,
        :'lowCreditNoteID', :'pendingCreditNoteID'
    ),
    'Should preserve every rejected credit-note work item'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
