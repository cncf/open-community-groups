-- Tests completing application-fee adjustment claims.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adjustmentID 'd7340000-0000-0000-0000-000000000001'
\set claimID 'd7340000-0000-0000-0000-000000000002'
\set communityID 'd7340000-0000-0000-0000-000000000003'
\set eventCategoryID 'd7340000-0000-0000-0000-000000000004'
\set eventID 'd7340000-0000-0000-0000-000000000005'
\set groupCategoryID 'd7340000-0000-0000-0000-000000000006'
\set groupID 'd7340000-0000-0000-0000-000000000007'
\set purchaseID 'd7340000-0000-0000-0000-000000000008'
\set ticketTypeID 'd7340000-0000-0000-0000-000000000009'
\set userID 'd7340000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the adjustment event
insert into community (
    banner_mobile_url, banner_url, community_id, description, display_name,
    logo_url, name
) values (
    'https://example.test/mobile.png', 'https://example.test/banner.png',
    :'communityID', 'Community', 'Community', 'https://example.test/logo.png',
    'complete-fee-adjustment-community'
);

-- Event category used by the adjustment event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the adjustment group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the adjustment event
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

-- Direct-charge purchase awaiting tax reconciliation
insert into event_purchase (
    amount_minor, charge_model, connected_seller_id, currency_code, event_id,
    event_purchase_id, event_ticket_type_id, final_platform_fee_amount_minor,
    payment_provider_id, provider_application_fee_id, provider_charge_id,
    provider_checkout_session_id, provider_object_account_id,
    provider_payment_reference, provider_total_minor,
    provisional_platform_fee_amount_minor, seller_snapshot, status,
    subtotal_excluding_tax_minor, tax_amount_minor, tax_behavior,
    tax_calculation_mode, tax_classification, ticket_title, user_id,
    venue_snapshot
) values (
    2500, 'direct-charge', 'acct_fee', 'USD', :'eventID', :'purchaseID',
    :'ticketTypeID', 80, 'stripe', 'fee_adjust', 'ch_adjust', 'cs_adjust',
    'acct_fee', 'pi_adjust', 2500, 100,
    '{"display_name":"Fiscal Sponsor"}'::jsonb, 'completed', 2300, 200,
    'inclusive', 'manual', 'professional-event-admission', 'General admission',
    :'userID', '{}'::jsonb
);

-- Processing application-fee adjustment claim
insert into event_purchase_application_fee_adjustment (
    amount_minor, attempt_count, claim_id, claimed_at,
    event_purchase_application_fee_adjustment_id, event_purchase_id,
    idempotency_key, kind, status
) values (
    20, 1, :'claimID', current_timestamp, :'adjustmentID', :'purchaseID',
    'complete-fee-adjustment', 'tax-reconciliation', 'processing'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should complete a claimed application-fee adjustment
select lives_ok(
    format(
        'select record_event_purchase_application_fee_adjustment_succeeded(%L, %L, %L)',
        :'adjustmentID', :'claimID', 'fr_adjust'
    ),
    'Should complete a claimed application-fee adjustment'
);

-- Should mark the tax-reconciled purchase financially reconciled
select results_eq(
    format($$
        select a.status, a.provider_application_fee_refund_id,
            p.financially_reconciled_at is not null
        from event_purchase_application_fee_adjustment a
        join event_purchase p using (event_purchase_id)
        where a.event_purchase_application_fee_adjustment_id = %L::uuid
    $$, :'adjustmentID'),
    $$ values ('completed'::text, 'fr_adjust'::text, true) $$,
    'Should mark the tax-reconciled purchase financially reconciled'
);

-- Should accept an idempotent application-fee completion replay
select lives_ok(
    format(
        'select record_event_purchase_application_fee_adjustment_succeeded(%L, %L, %L)',
        :'adjustmentID', :'claimID', 'fr_adjust'
    ),
    'Should accept an idempotent application-fee completion replay'
);

-- Should reject a conflicting application-fee completion replay
select throws_ok(
    format(
        'select record_event_purchase_application_fee_adjustment_succeeded(%L, %L, %L)',
        :'adjustmentID', :'claimID', 'fr_other'
    ),
    'application-fee adjustment has a different provider refund',
    'Should reject a conflicting application-fee completion replay'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
