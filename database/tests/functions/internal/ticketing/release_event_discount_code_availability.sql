-- Tests releasing event discount code availability.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

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

-- Community owning the discounted event
select fx_community(:'communityID');

-- Event category for the discounted event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category for the organizing group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group organizing the discounted event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event owning both discount codes
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Limited discount code and unlimited discount code
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

-- Should release limited and unlimited discount codes
select lives_ok(
    format($$
        select release_event_discount_code_availability(
            %L::uuid
        );
        select release_event_discount_code_availability(
            %L::uuid
        );
    $$, :'limitedDiscountID', :'unlimitedDiscountID'),
    'Should release limited and unlimited discount codes'
);

-- Should restore limited discount codes and leave unlimited ones untouched
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
    'Should restore limited discount codes and leave unlimited ones untouched'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
