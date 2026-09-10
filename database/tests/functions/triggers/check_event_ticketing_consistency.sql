-- Tests the settled ticketing shape enforced across event pricing tables.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ab1b0000-0000-0000-0000-000000000001'
\set discountCodeID 'ab1b0000-0000-0000-0000-000000000002'
\set eventCategoryID 'ab1b0000-0000-0000-0000-000000000003'
\set freeEventID 'ab1b0000-0000-0000-0000-000000000004'
\set freePriceWindowID 'ab1b0000-0000-0000-0000-000000000005'
\set freeTicketTypeID 'ab1b0000-0000-0000-0000-000000000006'
\set groupCategoryID 'ab1b0000-0000-0000-0000-000000000007'
\set groupID 'ab1b0000-0000-0000-0000-000000000008'
\set paidEventID 'ab1b0000-0000-0000-0000-000000000009'
\set paidPriceWindowID 'ab1b0000-0000-0000-0000-00000000000a'
\set paidTicketTypeID 'ab1b0000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Free event without payment configuration
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, slug, timezone)
values (:'freeEventID', 'Free event', :'eventCategoryID', 'virtual', :'groupID', 'Free Event', 'free-event', 'UTC');

-- Paid event with a payment currency
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, payment_currency_code, slug, timezone)
values (:'paidEventID', 'Paid event', :'eventCategoryID', 'virtual', :'groupID', 'Paid Event', 'USD', 'paid-event', 'UTC');

-- Ticket tier of the free event
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'freeTicketTypeID', :'freeEventID', 1, 10, 'General admission');

-- Ticket tier of the paid event
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'paidTicketTypeID', :'paidEventID', 1, 10, 'General admission');

-- Zero price window of the free event
insert into event_ticket_price_window (amount_minor, event_ticket_price_window_id, event_ticket_type_id)
values (0, :'freePriceWindowID', :'freeTicketTypeID');

-- Positive price window of the paid event
insert into event_ticket_price_window (amount_minor, event_ticket_price_window_id, event_ticket_type_id)
values (2000, :'paidPriceWindowID', :'paidTicketTypeID');

-- Discount code of the paid event
insert into event_discount_code (event_discount_code_id, event_id, code, kind, title, amount_minor)
values (:'discountCodeID', :'paidEventID', 'SAVE10', 'fixed_amount', 'Launch', 500);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Check the deferred constraint triggers at the end of each statement
set constraints
    event_ticketing_consistency_on_event,
    event_ticketing_consistency_on_event_discount_code,
    event_ticketing_consistency_on_event_ticket_price_window,
    event_ticketing_consistency_on_event_ticket_type
    immediate;

-- Should accept clearing all payment-only configuration together
select lives_ok(
    format(
        $$
            with discounts as (
                delete from event_discount_code where event_id = %L::uuid
            ),
            currency as (
                update event set payment_currency_code = null where event_id = %L::uuid
            )
            update event_ticket_price_window set amount_minor = 0 where event_ticket_price_window_id = %L::uuid
        $$,
        :'paidEventID',
        :'paidEventID',
        :'paidPriceWindowID'
    ),
    'Should accept clearing all payment-only configuration together'
);

-- Should accept positive pricing and a payment currency written together
select lives_ok(
    format(
        $$
            with currency as (
                update event set payment_currency_code = 'USD' where event_id = %L::uuid
            )
            update event_ticket_price_window set amount_minor = 2000 where event_ticket_price_window_id = %L::uuid
        $$,
        :'paidEventID',
        :'paidPriceWindowID'
    ),
    'Should accept positive pricing and a payment currency written together'
);

-- Should accept discount codes once positive pricing exists
select lives_ok(
    format(
        $$
            insert into event_discount_code (event_discount_code_id, event_id, code, kind, title, amount_minor)
            values (%L::uuid, %L::uuid, 'SAVE10', 'fixed_amount', 'Launch', 500)
        $$,
        :'discountCodeID',
        :'paidEventID'
    ),
    'Should accept discount codes once positive pricing exists'
);

-- Should accept deleting an event along with its ticketing rows
select lives_ok(
    format($$delete from event where event_id = %L::uuid$$, :'paidEventID'),
    'Should accept deleting an event along with its ticketing rows'
);

-- Should reject a payment currency when the event has no positive ticket pricing
select throws_ok(
    format($$update event set payment_currency_code = 'USD' where event_id = %L::uuid$$, :'freeEventID'),
    'OCG01',
    'payment_currency_code requires positive ticket pricing',
    'Should reject a payment currency when the event has no positive ticket pricing'
);

-- Should reject discount codes when the event has no positive ticket pricing
select throws_ok(
    format(
        $$
            insert into event_discount_code (event_discount_code_id, event_id, code, kind, title, amount_minor)
            values (gen_random_uuid(), %L::uuid, 'FREE10', 'fixed_amount', 'Launch', 500)
        $$,
        :'freeEventID'
    ),
    'OCG01',
    'discount_codes require positive ticket pricing',
    'Should reject discount codes when the event has no positive ticket pricing'
);

-- Should reject positive pricing without a payment currency
select throws_ok(
    format($$update event_ticket_price_window set amount_minor = 1500 where event_ticket_price_window_id = %L::uuid$$, :'freePriceWindowID'),
    'OCG01',
    'positive ticket pricing requires payment_currency_code',
    'Should reject positive pricing without a payment currency'
);

-- Should reject a positive ticket tier moved to an event without a payment currency
select throws_ok(
    format(
        $$
            with priced as (
                update event_ticket_price_window set amount_minor = 1500 where event_ticket_price_window_id = %L::uuid
            )
            update event_ticket_type set event_id = %L::uuid where event_ticket_type_id = %L::uuid
        $$,
        :'freePriceWindowID',
        :'freeEventID',
        :'freeTicketTypeID'
    ),
    'OCG01',
    'positive ticket pricing requires payment_currency_code',
    'Should reject a positive ticket tier moved to an event without a payment currency'
);

-- Should reject wiring the trigger to an unsupported table
select throws_ok(
    format(
        $$
            create trigger event_ticketing_consistency_on_region
                after insert on region
                for each row
                execute function check_event_ticketing_consistency();
            insert into region (community_id, name)
            values (%L::uuid, 'Unsupported');
        $$,
        :'communityID'
    ),
    'unsupported event ticketing consistency trigger table: region',
    'Should reject wiring the trigger to an unsupported table'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
