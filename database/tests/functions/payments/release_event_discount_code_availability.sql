-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79330000-0000-0000-0000-000000000001'
\set eventCategoryID '79330000-0000-0000-0000-000000000002'
\set eventID '79330000-0000-0000-0000-000000000003'
\set groupCategoryID '79330000-0000-0000-0000-000000000006'
\set groupID '79330000-0000-0000-0000-000000000007'
\set limitedDiscountID '79330000-0000-0000-0000-000000000004'
\set unlimitedDiscountID '79330000-0000-0000-0000-000000000005'

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
    'release-discount-community',
    'Release Discount Community',
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
    'Release Discount Group',
    'release-discount-group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_release_discount')
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
    'Release Discount Event',
    'release-discount-event',
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
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'limitedDiscountID',
    true,
    500,
    0,
    true,
    'SAVE5',
    :'eventID',
    'fixed_amount',
    'Save 5'
), (
    :'unlimitedDiscountID',
    true,
    500,
    null,
    false,
    'OPEN',
    :'eventID',
    'fixed_amount',
    'Open'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should restore one redemption by default for limited discount codes
select lives_ok(
    format($$select release_event_discount_code_availability(%L::uuid)$$, :'limitedDiscountID'),
    'Should restore one redemption by default for limited discount codes'
);

-- Should restore multiple redemptions when a quantity is provided
select lives_ok(
    format($$select release_event_discount_code_availability(%L::uuid, 2)$$, :'limitedDiscountID'),
    'Should restore multiple redemptions when a quantity is provided'
);

-- Should leave unlimited discount codes untouched
select results_eq(
    format($$
        select
            (
                select available::text
                from event_discount_code
                where event_discount_code_id = %L::uuid
            ),
            (
                select available::text
                from event_discount_code
                where event_discount_code_id = %L::uuid
            )
    $$, :'limitedDiscountID', :'unlimitedDiscountID'),
    $$ values ('3'::text, null::text) $$,
    'Should leave unlimited discount codes untouched'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
