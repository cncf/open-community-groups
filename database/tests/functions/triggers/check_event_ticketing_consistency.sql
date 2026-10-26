-- Tests the settled ticketing shape enforced across event pricing tables.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set clearedDiscountCodeID 'ab1b0000-0000-0000-0000-000000000001'
\set clearedEventID 'ab1b0000-0000-0000-0000-000000000002'
\set clearedPriceWindowID 'ab1b0000-0000-0000-0000-000000000003'
\set clearedTicketTypeID 'ab1b0000-0000-0000-0000-000000000004'
\set communityID 'ab1b0000-0000-0000-0000-000000000005'
\set currencyRemainsEventID 'ab1b0000-0000-0000-0000-000000000006'
\set currencyRemainsPriceWindowID 'ab1b0000-0000-0000-0000-000000000007'
\set currencyRemainsTicketTypeID 'ab1b0000-0000-0000-0000-000000000008'
\set deletedDiscountCodeID 'ab1b0000-0000-0000-0000-000000000009'
\set deletedEventID 'ab1b0000-0000-0000-0000-00000000000a'
\set deletedPriceWindowID 'ab1b0000-0000-0000-0000-00000000000b'
\set deletedTicketTypeID 'ab1b0000-0000-0000-0000-00000000000c'
\set discountAddedDiscountCodeID 'ab1b0000-0000-0000-0000-00000000000d'
\set discountAddedEventID 'ab1b0000-0000-0000-0000-00000000000e'
\set discountAddedPriceWindowID 'ab1b0000-0000-0000-0000-00000000000f'
\set discountAddedTicketTypeID 'ab1b0000-0000-0000-0000-000000000010'
\set discountsRemainDiscountCodeID 'ab1b0000-0000-0000-0000-000000000011'
\set discountsRemainEventID 'ab1b0000-0000-0000-0000-000000000012'
\set discountsRemainPriceWindowID 'ab1b0000-0000-0000-0000-000000000013'
\set discountsRemainTicketTypeID 'ab1b0000-0000-0000-0000-000000000014'
\set eventCategoryID 'ab1b0000-0000-0000-0000-000000000015'
\set freeEventID 'ab1b0000-0000-0000-0000-000000000016'
\set freePriceWindowID 'ab1b0000-0000-0000-0000-000000000017'
\set freeTicketTypeID 'ab1b0000-0000-0000-0000-000000000018'
\set groupCategoryID 'ab1b0000-0000-0000-0000-000000000019'
\set groupID 'ab1b0000-0000-0000-0000-00000000001a'
\set repricedEventID 'ab1b0000-0000-0000-0000-00000000001b'
\set repricedPriceWindowID 'ab1b0000-0000-0000-0000-00000000001c'
\set repricedTicketTypeID 'ab1b0000-0000-0000-0000-00000000001d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Paid event whose payment-only configuration is cleared
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, payment_currency_code, slug, timezone)
values (:'clearedEventID', 'Cleared event', :'eventCategoryID', 'virtual', :'groupID', 'Cleared Event', 'USD', 'cleared-event', 'UTC');

-- Paid event whose last positive price is removed while the currency remains
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, payment_currency_code, slug, timezone)
values (:'currencyRemainsEventID', 'Currency remains event', :'eventCategoryID', 'virtual', :'groupID', 'Currency Remains Event', 'USD', 'currency-remains-event', 'UTC');

-- Paid event deleted along with its ticketing rows
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, payment_currency_code, slug, timezone)
values (:'deletedEventID', 'Deleted event', :'eventCategoryID', 'virtual', :'groupID', 'Deleted Event', 'USD', 'deleted-event', 'UTC');

-- Paid event without discount codes that receives one
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, payment_currency_code, slug, timezone)
values (:'discountAddedEventID', 'Discount added event', :'eventCategoryID', 'virtual', :'groupID', 'Discount Added Event', 'USD', 'discount-added-event', 'UTC');

-- Paid event whose last positive price is removed while discounts remain
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, payment_currency_code, slug, timezone)
values (:'discountsRemainEventID', 'Discounts remain event', :'eventCategoryID', 'virtual', :'groupID', 'Discounts Remain Event', 'USD', 'discounts-remain-event', 'UTC');

-- Free event without payment configuration
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, slug, timezone)
values (:'freeEventID', 'Free event', :'eventCategoryID', 'virtual', :'groupID', 'Free Event', 'free-event', 'UTC');

-- Free event that receives positive pricing and a payment currency together
insert into event (event_id, description, event_category_id, event_kind_id, group_id, name, slug, timezone)
values (:'repricedEventID', 'Repriced event', :'eventCategoryID', 'virtual', :'groupID', 'Repriced Event', 'repriced-event', 'UTC');

-- Discount code of the cleared event
insert into event_discount_code (event_discount_code_id, event_id, code, kind, title, amount_minor)
values (:'clearedDiscountCodeID', :'clearedEventID', 'SAVE10', 'fixed_amount', 'Launch', 500);

-- Discount code of the deleted event
insert into event_discount_code (event_discount_code_id, event_id, code, kind, title, amount_minor)
values (:'deletedDiscountCodeID', :'deletedEventID', 'SAVE10', 'fixed_amount', 'Launch', 500);

-- Discount code of the event whose discounts remain
insert into event_discount_code (event_discount_code_id, event_id, code, kind, title, amount_minor)
values (:'discountsRemainDiscountCodeID', :'discountsRemainEventID', 'SAVE10', 'fixed_amount', 'Launch', 500);

-- Ticket tier of the cleared event
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'clearedTicketTypeID', :'clearedEventID', 1, 10, 'General admission');

-- Ticket tier of the event whose currency remains
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'currencyRemainsTicketTypeID', :'currencyRemainsEventID', 1, 10, 'General admission');

-- Ticket tier of the deleted event
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'deletedTicketTypeID', :'deletedEventID', 1, 10, 'General admission');

-- Ticket tier of the event that receives a discount code
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'discountAddedTicketTypeID', :'discountAddedEventID', 1, 10, 'General admission');

-- Ticket tier of the event whose discounts remain
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'discountsRemainTicketTypeID', :'discountsRemainEventID', 1, 10, 'General admission');

-- Ticket tier of the free event
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'freeTicketTypeID', :'freeEventID', 1, 10, 'General admission');

-- Ticket tier of the repriced event
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'repricedTicketTypeID', :'repricedEventID', 1, 10, 'General admission');

-- Positive price window of the cleared event
insert into event_ticket_price_window (amount_minor, event_ticket_price_window_id, event_ticket_type_id)
values (2000, :'clearedPriceWindowID', :'clearedTicketTypeID');

-- Positive price window of the event whose currency remains
insert into event_ticket_price_window (amount_minor, event_ticket_price_window_id, event_ticket_type_id)
values (2000, :'currencyRemainsPriceWindowID', :'currencyRemainsTicketTypeID');

-- Positive price window of the deleted event
insert into event_ticket_price_window (amount_minor, event_ticket_price_window_id, event_ticket_type_id)
values (2000, :'deletedPriceWindowID', :'deletedTicketTypeID');

-- Positive price window of the event that receives a discount code
insert into event_ticket_price_window (amount_minor, event_ticket_price_window_id, event_ticket_type_id)
values (2000, :'discountAddedPriceWindowID', :'discountAddedTicketTypeID');

-- Positive price window of the event whose discounts remain
insert into event_ticket_price_window (amount_minor, event_ticket_price_window_id, event_ticket_type_id)
values (2000, :'discountsRemainPriceWindowID', :'discountsRemainTicketTypeID');

-- Zero price window of the free event
insert into event_ticket_price_window (amount_minor, event_ticket_price_window_id, event_ticket_type_id)
values (0, :'freePriceWindowID', :'freeTicketTypeID');

-- Zero price window of the repriced event
insert into event_ticket_price_window (amount_minor, event_ticket_price_window_id, event_ticket_type_id)
values (0, :'repricedPriceWindowID', :'repricedTicketTypeID');

-- Session-local table that probes the unsupported-table branch without locking shared tables
create temporary table ticketing_probe (event_id uuid);

-- Trigger wiring on the probe table
create trigger ticketing_probe_consistency
    after insert on ticketing_probe
    for each row
    execute function check_event_ticketing_consistency();

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
        :'clearedEventID',
        :'clearedEventID',
        :'clearedPriceWindowID'
    ),
    'Should accept clearing all payment-only configuration together'
);

-- Should accept deleting an event along with its ticketing rows
select lives_ok(
    format($$delete from event where event_id = %L::uuid$$, :'deletedEventID'),
    'Should accept deleting an event along with its ticketing rows'
);

-- Should accept discount codes once positive pricing exists
select lives_ok(
    format(
        $$
            insert into event_discount_code (event_discount_code_id, event_id, code, kind, title, amount_minor)
            values (%L::uuid, %L::uuid, 'SAVE10', 'fixed_amount', 'Launch', 500)
        $$,
        :'discountAddedDiscountCodeID',
        :'discountAddedEventID'
    ),
    'Should accept discount codes once positive pricing exists'
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
        :'repricedEventID',
        :'repricedPriceWindowID'
    ),
    'Should accept positive pricing and a payment currency written together'
);

-- Should reject a payment currency when the event has no positive ticket pricing
select throws_ok(
    format($$update event set payment_currency_code = 'USD' where event_id = %L::uuid$$, :'freeEventID'),
    'OCG01',
    'payment_currency_code requires positive ticket pricing',
    'Should reject a payment currency when the event has no positive ticket pricing'
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

-- Should reject removing the last positive price while discounts remain
select throws_ok(
    format(
        $$
            with currency as (
                update event set payment_currency_code = null where event_id = %L::uuid
            )
            update event_ticket_price_window set amount_minor = 0 where event_ticket_price_window_id = %L::uuid
        $$,
        :'discountsRemainEventID',
        :'discountsRemainPriceWindowID'
    ),
    'OCG01',
    'discount_codes require positive ticket pricing',
    'Should reject removing the last positive price while discounts remain'
);

-- Should reject removing the last positive price while the payment currency remains
select throws_ok(
    format(
        $$update event_ticket_price_window set amount_minor = 0 where event_ticket_price_window_id = %L::uuid$$,
        :'currencyRemainsPriceWindowID'
    ),
    'OCG01',
    'payment_currency_code requires positive ticket pricing',
    'Should reject removing the last positive price while the payment currency remains'
);

-- Should reject wiring the trigger to an unsupported table
select throws_ok(
    $$insert into ticketing_probe (event_id) values (null)$$,
    'P0001',
    'unsupported event ticketing consistency trigger table: ticketing_probe',
    'Should reject wiring the trigger to an unsupported table'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
