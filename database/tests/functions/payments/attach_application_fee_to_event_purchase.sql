-- Tests attaching asynchronously created direct-charge application fees.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd7320000-0000-0000-0000-000000000001'
\set eventCategoryID 'd7320000-0000-0000-0000-000000000002'
\set eventID 'd7320000-0000-0000-0000-000000000003'
\set groupCategoryID 'd7320000-0000-0000-0000-000000000004'
\set groupID 'd7320000-0000-0000-0000-000000000005'
\set purchaseID 'd7320000-0000-0000-0000-000000000006'
\set ticketTypeID 'd7320000-0000-0000-0000-000000000007'
\set userID 'd7320000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the fee-bearing event
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.test/mobile.png',
    'https://example.test/banner.png',
    :'communityID',
    'Community',
    'Community',
    'https://example.test/logo.png',
    'attach-application-fee-community'
);

-- Event category used by the purchase
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the purchase group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the purchase event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Attendee owning the purchase
insert into "user" (auth_hash, email, user_id, username)
values ('user', 'user@example.test', :'userID', 'user');

-- Event snapshotted by the purchase
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    slug,
    timezone
) values (
    'Event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Event',
    'USD',
    'event',
    'UTC'
);

-- Ticket type snapshotted by the purchase
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (:'eventID', :'ticketTypeID', 1, 10, 'General admission');

-- Completed direct-charge purchase awaiting its asynchronous application fee
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    connected_seller_id,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
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
) values (
    2500,
    'direct-charge',
    current_timestamp,
    'acct_application_fee',
    'USD',
    :'eventID',
    :'purchaseID',
    :'ticketTypeID',
    62,
    'stripe',
    'ch_application_fee',
    'cs_application_fee',
    'acct_application_fee',
    'pi_application_fee',
    2500,
    62,
    '{"display_name":"Fiscal Sponsor"}'::jsonb,
    'completed',
    2500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'userID',
    '{}'::jsonb
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a blank application-fee identifier
select throws_ok(
    $$ select attach_application_fee_to_event_purchase(
        'stripe', 'acct_application_fee', 'ch_application_fee', ' ', 62
    ) $$,
    'application fee is missing provider context',
    'Should reject a blank application-fee identifier'
);

-- Should reject a blank connected seller
select throws_ok(
    $$ select attach_application_fee_to_event_purchase(
        'stripe', ' ', 'ch_application_fee', 'fee_application_fee', 62
    ) $$,
    'application fee is missing provider context',
    'Should reject a blank connected seller'
);

-- Should reject a blank provider charge
select throws_ok(
    $$ select attach_application_fee_to_event_purchase(
        'stripe', 'acct_application_fee', ' ', 'fee_application_fee', 62
    ) $$,
    'application fee is missing provider context',
    'Should reject a blank provider charge'
);

-- Should reject an amount that does not match the purchase snapshot
select throws_ok(
    $$ select attach_application_fee_to_event_purchase(
        'stripe', 'acct_application_fee', 'ch_application_fee',
        'fee_application_fee', 61
    ) $$,
    'application fee amount does not match the purchase',
    'Should reject an amount that does not match the purchase snapshot'
);

-- Should reject a missing application-fee amount
select throws_ok(
    $$ select attach_application_fee_to_event_purchase(
        'stripe', 'acct_application_fee', 'ch_application_fee',
        'fee_application_fee', null
    ) $$,
    'application fee amount must be positive',
    'Should reject a missing application-fee amount'
);

-- Should reject a non-positive application-fee amount
select throws_ok(
    $$ select attach_application_fee_to_event_purchase(
        'stripe', 'acct_application_fee', 'ch_application_fee',
        'fee_application_fee', 0
    ) $$,
    'application fee amount must be positive',
    'Should reject a non-positive application-fee amount'
);

-- Should reject the wrong connected seller scope
select throws_ok(
    $$ select attach_application_fee_to_event_purchase(
        'stripe', 'acct_other', 'ch_application_fee', 'fee_application_fee', 62
    ) $$,
    'direct-charge purchase not found for application fee',
    'Should reject the wrong connected seller scope'
);

-- Should reject the wrong provider charge scope
select throws_ok(
    $$ select attach_application_fee_to_event_purchase(
        'stripe', 'acct_application_fee', 'ch_other', 'fee_application_fee', 62
    ) $$,
    'direct-charge purchase not found for application fee',
    'Should reject the wrong provider charge scope'
);

-- Should reject the wrong provider scope
select throws_ok(
    $$ select attach_application_fee_to_event_purchase(
        'other', 'acct_application_fee', 'ch_application_fee',
        'fee_application_fee', 62
    ) $$,
    'direct-charge purchase not found for application fee',
    'Should reject the wrong provider scope'
);

-- Should attach the asynchronous application fee
select lives_ok(
    $$ select attach_application_fee_to_event_purchase(
        'stripe', 'acct_application_fee', 'ch_application_fee',
        'fee_application_fee', 62
    ) $$,
    'Should attach the asynchronous application fee'
);

-- Should persist the provider application-fee identifier
select is(
    (
        select provider_application_fee_id
        from event_purchase
        where event_purchase_id = :'purchaseID'::uuid
    ),
    'fee_application_fee',
    'Should persist the provider application-fee identifier'
);

-- Should accept replaying the same application fee
select lives_ok(
    $$ select attach_application_fee_to_event_purchase(
        'stripe', 'acct_application_fee', 'ch_application_fee',
        'fee_application_fee', 62
    ) $$,
    'Should accept replaying the same application fee'
);

-- Should reject a conflicting second application fee
select throws_ok(
    $$ select attach_application_fee_to_event_purchase(
        'stripe', 'acct_application_fee', 'ch_application_fee',
        'fee_conflict', 62
    ) $$,
    'purchase has a different provider application fee',
    'Should reject a conflicting second application fee'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
