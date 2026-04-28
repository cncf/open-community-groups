-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79310000-0000-0000-0000-000000000001'
\set discountCodeID '79310000-0000-0000-0000-000000000002'
\set eventCategoryID '79310000-0000-0000-0000-000000000003'
\set eventID '79310000-0000-0000-0000-000000000004'
\set eventTicketTypeID '79310000-0000-0000-0000-000000000005'
\set groupCategoryID '79310000-0000-0000-0000-000000000006'
\set groupID '79310000-0000-0000-0000-000000000007'
\set otherCommunityID '79310000-0000-0000-0000-000000000008'
\set pendingPurchaseID '79310000-0000-0000-0000-000000000009'
\set priceWindowID '79310000-0000-0000-0000-000000000010'
\set userID '79310000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url
)
values
    (
        :'communityID',
        'cancel-checkout-community',
        'Cancel Checkout Community',
        'Test',
        'https://e/logo.png',
        'https://e/banner-mobile.png',
        'https://e/banner.png'
    ),
    (
        :'otherCommunityID',
        'other-cancel-checkout-community',
        'Other Cancel Checkout Community',
        'Test',
        'https://e/logo.png',
        'https://e/banner-mobile.png',
        'https://e/banner.png'
    );

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
    'Cancel Checkout Group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_cancel_checkout'),
    'cancel-checkout-group'
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
    'Cancel Checkout Event',
    'cancel-checkout-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
);

-- Ticket type
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'eventTicketTypeID', :'eventID', 1, 10, 'General admission');

-- Price window
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    2500,
    :'eventTicketTypeID'
);

-- Discount code
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
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
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    status,
    ticket_title,
    user_id
) values (
    :'pendingPurchaseID',
    2000,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'eventTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_cancel_checkout',
    'https://checkout.stripe.test/cs_cancel_checkout',
    'pending',
    'General admission',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore checkouts outside the requested community
select lives_ok(
    $$select cancel_event_checkout(
        '79310000-0000-0000-0000-000000000008'::uuid,
        '79310000-0000-0000-0000-000000000004'::uuid,
        '79310000-0000-0000-0000-000000000011'::uuid
    )$$,
    'Should ignore checkouts outside the requested community'
);

-- Should leave unmatched community checkout state unchanged
select results_eq(
    $$
        select
            (
                select available
                from event_discount_code
                where event_discount_code_id = '79310000-0000-0000-0000-000000000002'::uuid
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = '79310000-0000-0000-0000-000000000009'::uuid
            )
    $$,
    $$ values (0::int, 'pending'::text) $$,
    'Should leave unmatched community checkout state unchanged'
);

-- Should cancel the attendee's active pending checkout
select lives_ok(
    $$select cancel_event_checkout(
        '79310000-0000-0000-0000-000000000001'::uuid,
        '79310000-0000-0000-0000-000000000004'::uuid,
        '79310000-0000-0000-0000-000000000011'::uuid
    )$$,
    'Should cancel the attendee active pending checkout'
);

-- Should expire the pending checkout and restore the reserved discount usage
select results_eq(
    $$
        select
            (
                select available
                from event_discount_code
                where event_discount_code_id = '79310000-0000-0000-0000-000000000002'::uuid
            ),
            (
                select hold_expires_at <= current_timestamp
                from event_purchase
                where event_purchase_id = '79310000-0000-0000-0000-000000000009'::uuid
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = '79310000-0000-0000-0000-000000000009'::uuid
            )
    $$,
    $$ values (1::int, true, 'expired'::text) $$,
    'Should expire the pending checkout and restore the reserved discount usage'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
