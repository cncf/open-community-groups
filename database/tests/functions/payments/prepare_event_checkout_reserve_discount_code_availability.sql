-- Tests reserving event checkout discount code availability.

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
\set groupCategoryID '79250000-0000-0000-0000-000000000006'
\set groupID '79250000-0000-0000-0000-000000000007'
\set limitedDiscountID '79250000-0000-0000-0000-000000000004'
\set unlimitedDiscountID '79250000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and categories
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_reserve_discount',
        'seller_display_name', 'Reserve Discount Fiscal Sponsor'
    )));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

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
    2,
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

-- Should reserve available inventory for limited discount codes
select lives_ok(
    format($$
        select prepare_event_checkout_reserve_discount_code_availability(
            %L::uuid
        );
        select prepare_event_checkout_reserve_discount_code_availability(
            %L::uuid
        );
    $$, :'limitedDiscountID', :'unlimitedDiscountID'),
    'Should reserve available inventory for limited discount codes'
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
    $$ values ('1'::text, null::text) $$,
    'Should leave unlimited discount codes untouched'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
