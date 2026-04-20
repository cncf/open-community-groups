-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79210000-0000-0000-0000-000000000001'
\set discountCodeID '79210000-0000-0000-0000-000000000002'
\set eventCategoryID '79210000-0000-0000-0000-000000000003'
\set eventID '79210000-0000-0000-0000-000000000004'
\set ticketTypeID '79210000-0000-0000-0000-000000000005'
\set groupCategoryID '79210000-0000-0000-0000-000000000006'
\set groupID '79210000-0000-0000-0000-000000000007'
\set priceWindowID '79210000-0000-0000-0000-000000000008'
\set purchaseID '79210000-0000-0000-0000-000000000009'
\set userID '79210000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'expire-replaced-community', 'Expire Replaced Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash-1', 'buyer@example.com', true, 'buyer');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, payment_recipient, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Expire Replaced Group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_expire_replaced'),
    'expire-replaced-group'
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
    'Expire Replaced Event',
    'expire-replaced-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
);

-- Ticket type
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'ticketTypeID', :'eventID', 1, 10, 'General admission');

-- Price window
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    2500,
    :'ticketTypeID'
);

-- Discount code
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    true,
    500,
    0,
    true,
    'SAVE5',
    :'eventID',
    'fixed_amount',
    'Save 5'
);

-- Pending purchase
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
    status,
    ticket_title,
    user_id
) values (
    :'purchaseID',
    2000,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'ticketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should expire the replaced pending purchase
select lives_ok(
    $$select prepare_event_checkout_expire_previous_hold('79210000-0000-0000-0000-000000000009'::uuid)$$,
    'Should expire the replaced pending purchase'
);

-- Should restore the reserved discount inventory
select results_eq(
    $$
        select
            (select hold_expires_at <= current_timestamp from event_purchase where event_purchase_id = '79210000-0000-0000-0000-000000000009'::uuid),
            (select status from event_purchase where event_purchase_id = '79210000-0000-0000-0000-000000000009'::uuid),
            (select available::text from event_discount_code where event_discount_code_id = '79210000-0000-0000-0000-000000000002'::uuid)
    $$,
    $$ values (true, 'expired'::text, '1'::text) $$,
    'Should restore the reserved discount inventory'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
