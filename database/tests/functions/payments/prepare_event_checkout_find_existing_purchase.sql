-- Tests finding reusable event checkout purchases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79230000-0000-0000-0000-000000000001'
\set eventCategoryID '79230000-0000-0000-0000-000000000002'
\set eventID '79230000-0000-0000-0000-000000000003'
\set groupCategoryID '79230000-0000-0000-0000-000000000006'
\set groupID '79230000-0000-0000-0000-000000000007'
\set offerID '79230000-0000-0000-0000-00000000001a'
\set offerPurchaseID '79230000-0000-0000-0000-00000000001b'
\set offerUserID '79230000-0000-0000-0000-00000000001c'
\set pendingPurchaseID '79230000-0000-0000-0000-000000000010'
\set priceWindowAID '79230000-0000-0000-0000-000000000008'
\set priceWindowBID '79230000-0000-0000-0000-000000000009'
\set primaryUserID '79230000-0000-0000-0000-000000000012'
\set recoveryOnlyPurchaseID '79230000-0000-0000-0000-000000000016'
\set recoveryOnlyPendingPurchaseID '79230000-0000-0000-0000-000000000019'
\set recoveryOnlyUserID '79230000-0000-0000-0000-000000000017'
\set recoveryPurchaseID '79230000-0000-0000-0000-000000000014'
\set recoveryReplacementPurchaseID '79230000-0000-0000-0000-000000000018'
\set recoveryUserID '79230000-0000-0000-0000-000000000015'
\set refundPendingOfferID '79230000-0000-0000-0000-00000000001d'
\set refundPendingPurchaseID '79230000-0000-0000-0000-00000000001e'
\set refundPendingUserID '79230000-0000-0000-0000-00000000001f'
\set refundPurchaseID '79230000-0000-0000-0000-000000000011'
\set secondaryUserID '79230000-0000-0000-0000-000000000013'
\set ticketTypeAID '79230000-0000-0000-0000-000000000004'
\set ticketTypeBID '79230000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'find-reusable-community',
    'Find Reusable Community',
    'Test',
    'https://e/banner-mobile.png',
    'https://e/banner.png',
    'https://e/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (
        :'primaryUserID',
        'hash-1',
        'primary@example.com',
        true,
        'primary-user'
    ),
    (
        :'secondaryUserID',
        'hash-2',
        'secondary@example.com',
        true,
        'secondary-user'
    ),
    (
        :'recoveryUserID',
        'hash-3',
        'recovery@example.com',
        true,
        'recovery-user'
    ),
    (
        :'offerUserID',
        'hash-5',
        'offer@example.com',
        true,
        'offer-user'
    ),
    (
        :'recoveryOnlyUserID',
        'hash-4',
        'recovery-only@example.com',
        true,
        'recovery-only-user'
    ),
    (
        :'refundPendingUserID',
        'hash-6',
        'refund-pending@example.com',
        true,
        'refund-pending-user'
    );

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    payment_recipient
)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Find Reusable Group',
    'find-reusable-group',
    jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_find_reusable',
        'seller_display_name', 'Reusable Purchase Fiscal Sponsor'
    )
);

-- Event
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    starts_at,
    payment_currency_code,
    published,
    published_at
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Find Reusable Event',
    'find-reusable-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
);

-- Ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
)
values
    (
        :'ticketTypeAID',
        :'eventID',
        1,
        10,
        'General admission'
    ),
    (
        :'ticketTypeBID',
        :'eventID',
        2,
        10,
        'VIP'
    );

-- Price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'priceWindowAID', 2500, :'ticketTypeAID'),
    (:'priceWindowBID', 4000, :'ticketTypeBID');

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
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
    fixtures.event_purchase_id::uuid,
    fixtures.amount_minor,
    fixtures.created_at,
    fixtures.currency_code,
    fixtures.discount_amount_minor,
    fixtures.discount_code,
    fixtures.event_id::uuid,
    fixtures.event_ticket_type_id::uuid,
    fixtures.hold_expires_at,
    fixtures.status,
    fixtures.ticket_title,
    fixtures.user_id::uuid,

    'direct-charge',
    'acct_find',
    case when fixtures.status <> 'pending' then 0 end,
    'stripe',
    case when fixtures.status <> 'pending' then 'ch_' || fixtures.event_purchase_id end,
    case when fixtures.status <> 'pending' then 'cs_' || fixtures.event_purchase_id end,
    'acct_find',
    case when fixtures.status <> 'pending' then 'pi_' || fixtures.event_purchase_id end,
    case when fixtures.status <> 'pending' then fixtures.amount_minor end,
    '{"connected_account_id":"acct_find","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    case when fixtures.status <> 'pending' then fixtures.amount_minor end,
    case when fixtures.status <> 'pending' then 0 end,
    'inclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
from (values (
    :'pendingPurchaseID',
    2000,
    now() - interval '1 hour',
    'USD',
    500,
    ' save5 ',
    :'eventID',
    :'ticketTypeAID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'primaryUserID'
), (
    :'refundPurchaseID',
    4000,
    now() - interval '30 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    null,
    'refund-requested',
    'VIP',
    :'secondaryUserID'
), (
    :'recoveryOnlyPurchaseID',
    4000,
    now() - interval '15 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    null,
    'refund-recovery-pending',
    'VIP',
    :'recoveryOnlyUserID'
), (
    :'recoveryOnlyPendingPurchaseID',
    4000,
    now() - interval '5 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    now() + interval '10 minutes',
    'pending',
    'VIP',
    :'recoveryOnlyUserID'
), (
    :'recoveryPurchaseID',
    4000,
    now() - interval '20 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    null,
    'refund-recovery-pending',
    'VIP',
    :'recoveryUserID'
), (
    :'recoveryReplacementPurchaseID',
    4000,
    now() - interval '10 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    null,
    'completed',
    'VIP',
    :'recoveryUserID'
)) as fixtures (
    event_purchase_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
);

-- Offer-linked pending purchase isolated from direct checkout lookups
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'offerID',
    2500,
    'USD',
    0,
    :'eventID',
    :'ticketTypeAID',
    current_timestamp + interval '1 hour',
    'approval',
    'checkout_pending',
    'General admission',
    :'offerUserID'
);

-- Offer retained while its late purchase payment is refunded automatically
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'refundPendingOfferID',
    2500,
    'USD',
    0,
    :'eventID',
    :'ticketTypeAID',
    current_timestamp + interval '1 hour',
    'approval',
    'checkout_pending',
    'General admission',
    :'refundPendingUserID'
);

-- Active pending purchase linked to the selected admission offer
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot,

    charge_model,
    connected_seller_id
) values (
    :'offerID',
    2500,
    'USD',
    0,
    :'eventID',
    :'offerPurchaseID',
    :'ticketTypeAID',
    current_timestamp + interval '15 minutes',
    'stripe',
    'acct_find',
    '{"connected_account_id":"acct_find","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'offerUserID',
    '{}'::jsonb,
    'direct-charge',
    'acct_find'
);

-- Refund-pending purchase linked to its selected admission offer
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    seller_snapshot,
    status,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot,

    charge_model,
    connected_seller_id,
    final_platform_fee_amount_minor
) values (
    :'refundPendingOfferID',
    2500,
    'USD',
    0,
    :'eventID',
    :'refundPendingPurchaseID',
    :'ticketTypeAID',
    null,
    'stripe',
    'ch_find_refund',
    'cs_find_refund',
    'acct_find',
    'pi_find_refund',
    2500,
    '{"connected_account_id":"acct_find","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'refund-pending',
    2500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'refundPendingUserID',
    '{}'::jsonb,
    'direct-charge',
    'acct_find',
    0
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should mark the pending purchase as matching when ticket and discount align
select results_eq(
    format($$
        select matches_selection::text
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'SAVE5'
        )
    $$, :'eventID', :'ticketTypeAID', :'primaryUserID'),
    $$ values ('true'::text) $$,
    'Should mark the pending purchase as matching when ticket and discount align'
);

-- Should mark the pending purchase as mismatched when the requested discount changes
select results_eq(
    format($$
        select matches_selection::text
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'SAVE10'
        )
    $$, :'eventID', :'ticketTypeAID', :'primaryUserID'),
    $$ values ('false'::text) $$,
    'Should mark the pending purchase as mismatched when the requested discount changes'
);

-- Should return the active pending purchase for the requested user and event
select results_eq(
    format($$
        select event_purchase_id::text, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'SAVE5'
        )
    $$, :'eventID', :'ticketTypeAID', :'primaryUserID'),
    format($$ values (%L::text, 'pending'::text) $$, :'pendingPurchaseID'),
    'Should return the active pending purchase for the requested user and event'
);

-- Should return the newer completed replacement before an older recovery purchase
select results_eq(
    format($$
        select event_purchase_id::text, matches_selection::text, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null
        )
    $$, :'eventID', :'ticketTypeBID', :'recoveryUserID'),
    format(
        $$ values (%L::text, 'true'::text, 'completed'::text) $$,
        :'recoveryReplacementPurchaseID'
    ),
    'Should return the newer completed replacement before an older recovery purchase'
);

-- Should return recovery before a newer pending replacement purchase
select results_eq(
    format($$
        select event_purchase_id::text, matches_selection::text, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null
        )
    $$, :'eventID', :'ticketTypeBID', :'recoveryOnlyUserID'),
    format(
        $$ values (%L::text, 'true'::text, 'refund-recovery-pending'::text) $$,
        :'recoveryOnlyPurchaseID'
    ),
    'Should return recovery before a newer pending replacement purchase'
);

-- Should return refund-requested purchases when no active pending purchase exists
select results_eq(
    format($$
        select event_purchase_id::text, matches_selection::text, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null
        )
    $$, :'eventID', :'ticketTypeBID', :'secondaryUserID'),
    format(
        $$ values (%L::text, 'true'::text, 'refund-requested'::text) $$,
        :'refundPurchaseID'
    ),
    'Should return refund-requested purchases when no active pending purchase exists'
);

-- Should exclude offer-linked purchases from direct checkout reuse
select is_empty(
    format(
        $$
        select event_purchase_id
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null
        )
        $$,
        :'eventID',
        :'ticketTypeAID',
        :'offerUserID'
    ),
    'Should exclude offer-linked purchases from direct checkout reuse'
);

-- Should reuse only the purchase linked to the selected offer
select results_eq(
    format(
        $$
        select event_purchase_id, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            %L::uuid
        )
        $$,
        :'eventID',
        :'ticketTypeAID',
        :'offerUserID',
        :'offerID'
    ),
    format(
        $$ values (%L::uuid, 'pending'::text) $$,
        :'offerPurchaseID'
    ),
    'Should reuse only the purchase linked to the selected offer'
);

-- Should retain an offer purchase while its automatic refund is pending
select results_eq(
    format(
        $$
        select event_purchase_id, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            %L::uuid
        )
        $$,
        :'eventID',
        :'ticketTypeAID',
        :'refundPendingUserID',
        :'refundPendingOfferID'
    ),
    format(
        $$ values (%L::uuid, 'refund-pending'::text) $$,
        :'refundPendingPurchaseID'
    ),
    'Should retain an offer purchase while its automatic refund is pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
