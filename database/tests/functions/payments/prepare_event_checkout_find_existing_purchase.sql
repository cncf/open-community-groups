-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '79230000-0000-0000-0000-000000000001'
\set eventCategoryID '79230000-0000-0000-0000-000000000002'
\set eventID '79230000-0000-0000-0000-000000000003'
\set groupCategoryID '79230000-0000-0000-0000-000000000006'
\set groupID '79230000-0000-0000-0000-000000000007'
\set pendingPurchaseID '79230000-0000-0000-0000-000000000010'
\set priceWindowAID '79230000-0000-0000-0000-000000000008'
\set priceWindowBID '79230000-0000-0000-0000-000000000009'
\set primaryUserID '79230000-0000-0000-0000-000000000012'
\set refundPurchaseID '79230000-0000-0000-0000-000000000011'
\set secondaryUserID '79230000-0000-0000-0000-000000000013'
\set ticketTypeAID '79230000-0000-0000-0000-000000000004'
\set ticketTypeBID '79230000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'find-reusable-alliance',
    'Find Reusable Alliance',
    'Test',
    'https://e/banner-mobile.png',
    'https://e/banner.png',
    'https://e/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Tech');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

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
    );

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    payment_recipient
)
values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Find Reusable Group',
    'find-reusable-group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_find_reusable')
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
    user_id
) values (
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
);

-- ============================================================================
-- TESTS
-- ============================================================================

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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
