-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79000000-0000-0000-0000-000000000001'
\set discountCodeID '79000000-0000-0000-0000-000000000002'
\set eventCategoryID '79000000-0000-0000-0000-000000000003'
\set activeEventID '79000000-0000-0000-0000-000000000004'
\set canceledEventID '79000000-0000-0000-0000-000000000005'
\set activeTicketTypeID '79000000-0000-0000-0000-000000000006'
\set canceledTicketTypeID '79000000-0000-0000-0000-000000000007'
\set groupCategoryID '79000000-0000-0000-0000-000000000008'
\set groupID '79000000-0000-0000-0000-000000000009'
\set activePriceWindowID '79000000-0000-0000-0000-000000000010'
\set canceledPriceWindowID '79000000-0000-0000-0000-000000000011'
\set purchaseCompleteID '79000000-0000-0000-0000-000000000012'
\set purchaseExpiredID '79000000-0000-0000-0000-000000000013'
\set purchaseCanceledID '79000000-0000-0000-0000-000000000014'
\set purchaseMissingRefID '79000000-0000-0000-0000-000000000015'
\set purchaseDoneID '79000000-0000-0000-0000-000000000016'
\set user1ID '79000000-0000-0000-0000-000000000017'
\set user2ID '79000000-0000-0000-0000-000000000018'
\set user3ID '79000000-0000-0000-0000-000000000019'
\set user4ID '79000000-0000-0000-0000-000000000020'
\set user5ID '79000000-0000-0000-0000-000000000021'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'complete-community', 'Complete Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'user1ID', 'hash-1', 'user1@example.com', true, 'buyer-1'),
    (:'user2ID', 'hash-2', 'user2@example.com', true, 'buyer-2'),
    (:'user3ID', 'hash-3', 'user3@example.com', true, 'buyer-3'),
    (:'user4ID', 'hash-4', 'user4@example.com', true, 'buyer-4'),
    (:'user5ID', 'hash-5', 'user5@example.com', true, 'buyer-5');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Complete Group', 'complete-group');

-- Events
insert into event (
    canceled,
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    starts_at,
    published,
    published_at
) values (
    false,
    :'activeEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Active Event',
    'active-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    true,
    now()
), (
    true,
    :'canceledEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Canceled Event',
    'canceled-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    false,
    null
);

-- Ticket types
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values
    (:'activeTicketTypeID', :'activeEventID', 1, 10, 'General admission'),
    (:'canceledTicketTypeID', :'canceledEventID', 1, 10, 'General admission');

-- Ticket price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'activePriceWindowID', 2500, :'activeTicketTypeID'),
    (:'canceledPriceWindowID', 2500, :'canceledTicketTypeID');

-- Discount code used by the expired purchase
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    available,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    500,
    0,
    'SAVE5',
    :'activeEventID',
    'fixed_amount',
    'Save 5'
);

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_payment_reference,
    status,
    ticket_title,
    user_id
) values (
    :'purchaseCompleteID',
    2500,
    'USD',
    0,
    null,
    null,
    :'activeEventID',
    :'activeTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_complete',
    null,
    'pending',
    'General admission',
    :'user1ID'
), (
    :'purchaseExpiredID',
    2000,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'activeEventID',
    :'activeTicketTypeID',
    now() - interval '15 minutes',
    'stripe',
    'cs_expired',
    'pi_expired',
    'pending',
    'General admission',
    :'user2ID'
), (
    :'purchaseCanceledID',
    2500,
    'USD',
    0,
    null,
    null,
    :'canceledEventID',
    :'canceledTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_canceled',
    'pi_canceled',
    'pending',
    'General admission',
    :'user3ID'
), (
    :'purchaseMissingRefID',
    2500,
    'USD',
    0,
    null,
    null,
    :'activeEventID',
    :'activeTicketTypeID',
    now() - interval '15 minutes',
    'stripe',
    'cs_missing_ref',
    null,
    'pending',
    'General admission',
    :'user4ID'
), (
    :'purchaseDoneID',
    2500,
    'USD',
    0,
    null,
    null,
    :'activeEventID',
    :'activeTicketTypeID',
    null,
    'stripe',
    'cs_done',
    'pi_done',
    'completed',
    'General admission',
    :'user5ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return noop when there is no matching checkout session
select is(
    reconcile_event_purchase_for_checkout_session('stripe', 'cs_missing', 'pi_missing')::jsonb,
    '{"outcome":"noop"}'::jsonb,
    'Should return noop when there is no matching checkout session'
);

-- Should complete a valid pending checkout session
select is(
    reconcile_event_purchase_for_checkout_session('stripe', 'cs_complete', 'pi_complete')::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'activeEventID'::uuid,
        'outcome', 'completed',
        'user_id', :'user1ID'::uuid
    ),
    'Should complete a valid pending checkout session'
);

-- Should persist the completed purchase fields and add the attendee
select results_eq(
    $$
        select
            (select completed_at is not null from event_purchase where event_purchase_id = '79000000-0000-0000-0000-000000000012'::uuid),
            (select hold_expires_at is null from event_purchase where event_purchase_id = '79000000-0000-0000-0000-000000000012'::uuid),
            (select provider_payment_reference from event_purchase where event_purchase_id = '79000000-0000-0000-0000-000000000012'::uuid),
            (select status from event_purchase where event_purchase_id = '79000000-0000-0000-0000-000000000012'::uuid),
            (select count(*)::int from event_attendee where event_id = '79000000-0000-0000-0000-000000000004'::uuid and user_id = '79000000-0000-0000-0000-000000000017'::uuid)
    $$,
    $$ values (true, true, 'pi_complete'::text, 'completed'::text, 1::int) $$,
    'Should persist the completed purchase fields and add the attendee'
);

-- Should require refund for expired local holds
select is(
    reconcile_event_purchase_for_checkout_session('stripe', 'cs_expired', null)::jsonb,
    jsonb_build_object(
        'amount_minor', 2000,
        'event_purchase_id', :'purchaseExpiredID'::uuid,
        'outcome', 'refund_required',
        'provider_payment_reference', 'pi_expired'
    ),
    'Should require refund for expired local holds'
);

-- Should persist the expired purchase fields and restore discount availability
select results_eq(
    $$
        select
            (select hold_expires_at is null from event_purchase where event_purchase_id = '79000000-0000-0000-0000-000000000013'::uuid),
            (select provider_payment_reference from event_purchase where event_purchase_id = '79000000-0000-0000-0000-000000000013'::uuid),
            (select status from event_purchase where event_purchase_id = '79000000-0000-0000-0000-000000000013'::uuid),
            (select available from event_discount_code where event_discount_code_id = '79000000-0000-0000-0000-000000000002'::uuid)
    $$,
    $$ values (true, 'pi_expired'::text, 'expired'::text, 1::int) $$,
    'Should persist the expired purchase fields and restore discount availability'
);

-- Should noop for already expired purchases after the refund handoff
select is(
    reconcile_event_purchase_for_checkout_session('stripe', 'cs_expired', null)::jsonb,
    '{"outcome":"noop"}'::jsonb,
    'Should noop for already expired purchases after the refund handoff'
);

-- Should not restore discount availability twice for already expired purchases
select is(
    (
        select available
        from event_discount_code
        where event_discount_code_id = :'discountCodeID'::uuid
    ),
    1,
    'Should not restore discount availability twice for already expired purchases'
);

-- Should require refund when the event can no longer be fulfilled
select is(
    reconcile_event_purchase_for_checkout_session('stripe', 'cs_canceled', null)::jsonb,
    jsonb_build_object(
        'amount_minor', 2500,
        'event_purchase_id', :'purchaseCanceledID'::uuid,
        'outcome', 'refund_required',
        'provider_payment_reference', 'pi_canceled'
    ),
    'Should require refund when the event can no longer be fulfilled'
);

-- Should persist the canceled purchase fields when refunding
select results_eq(
    $$
        select
            hold_expires_at is null,
            provider_payment_reference,
            status
        from event_purchase
        where event_purchase_id = '79000000-0000-0000-0000-000000000014'::uuid
    $$,
    $$ values (true, 'pi_canceled'::text, 'expired'::text) $$,
    'Should persist the canceled purchase fields when refunding'
);

-- Should reject refund-required paths without a provider payment reference
select throws_ok(
    $$select reconcile_event_purchase_for_checkout_session('stripe', 'cs_missing_ref', null)$$,
    'provider payment reference is required for refund',
    'Should reject refund-required paths without a provider payment reference'
);

-- Should noop for already completed purchases
select is(
    reconcile_event_purchase_for_checkout_session('stripe', 'cs_done', null)::jsonb,
    '{"outcome":"noop"}'::jsonb,
    'Should noop for already completed purchases'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
