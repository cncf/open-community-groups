-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79250000-0000-0000-0000-000000000001'
\set eventCategoryID '79250000-0000-0000-0000-000000000002'
\set eventID '79250000-0000-0000-0000-000000000003'
\set limitedDiscountID '79250000-0000-0000-0000-000000000004'
\set unlimitedDiscountID '79250000-0000-0000-0000-000000000005'
\set groupCategoryID '79250000-0000-0000-0000-000000000006'
\set groupID '79250000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'reserve-discount-community', 'Reserve Discount Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, payment_recipient, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Reserve Discount Group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_reserve_discount'),
    'reserve-discount-group'
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
    'Reserve Discount Event',
    'reserve-discount-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
);

-- Discount codes
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    available,
    code,
    event_id,
    kind,
    title
) values (
    :'limitedDiscountID',
    true,
    500,
    2,
    'SAVE5',
    :'eventID',
    'fixed_amount',
    'Save 5'
), (
    :'unlimitedDiscountID',
    true,
    500,
    null,
    'OPEN',
    :'eventID',
    'fixed_amount',
    'Open'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reserve available inventory for limited discount codes
select lives_ok(
    $$
        select prepare_event_checkout_reserve_discount_code_availability(
            '79250000-0000-0000-0000-000000000004'::uuid
        );
        select prepare_event_checkout_reserve_discount_code_availability(
            '79250000-0000-0000-0000-000000000005'::uuid
        );
    $$,
    'Should reserve available inventory for limited discount codes'
);

-- Should leave unlimited discount codes untouched
select results_eq(
    $$
        select
            (
                select available::text
                from event_discount_code
                where event_discount_code_id = '79250000-0000-0000-0000-000000000004'::uuid
            ),
            (
                select available::text
                from event_discount_code
                where event_discount_code_id = '79250000-0000-0000-0000-000000000005'::uuid
            )
    $$,
    $$ values ('1'::text, null::text) $$,
    'Should leave unlimited discount codes untouched'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
