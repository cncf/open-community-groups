-- Tests event purchase ticket type and discount code ownership constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c0070000-0000-0000-0000-000000000001'
\set discountCodeID 'c0070000-0000-0000-0000-000000000002'
\set eventCategoryID 'c0070000-0000-0000-0000-000000000003'
\set eventID 'c0070000-0000-0000-0000-000000000004'
\set eventOtherID 'c0070000-0000-0000-0000-000000000005'
\set groupCategoryID 'c0070000-0000-0000-0000-000000000006'
\set groupID 'c0070000-0000-0000-0000-000000000007'
\set otherDiscountCodeID 'c0070000-0000-0000-0000-000000000008'
\set otherTicketTypeID 'c0070000-0000-0000-0000-000000000009'
\set ticketTypeID 'c0070000-0000-0000-0000-00000000000a'
\set userDiscountAcceptedID 'c0070000-0000-0000-0000-00000000000b'
\set userDiscountRejectedID 'c0070000-0000-0000-0000-00000000000c'
\set userTicketTypeAcceptedID 'c0070000-0000-0000-0000-00000000000d'
\set userTicketTypeRejectedID 'c0070000-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Buyer of the accepted discounted purchase
select fx_user(:'userDiscountAcceptedID');

-- Buyer of the rejected discounted purchase
select fx_user(:'userDiscountRejectedID');

-- Buyer of the accepted ticket type purchase
select fx_user(:'userTicketTypeAcceptedID');

-- Buyer of the rejected ticket type purchase
select fx_user(:'userTicketTypeRejectedID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event receiving the purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', '{"payment_currency_code": "USD"}');

-- Sibling event owning the foreign ticket type and discount code
select fx_event(:'eventOtherID', :'groupID', :'eventCategoryID', '{"payment_currency_code": "USD"}');

-- Discount code of the purchased event
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    100,
    'OWN',
    :'eventID',
    'fixed_amount',
    'Own discount'
);

-- Discount code of the sibling event
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    :'otherDiscountCodeID',
    100,
    'OTHER',
    :'eventOtherID',
    'fixed_amount',
    'Other discount'
);

-- Ticket type of the purchased event
select fx_event_ticket_type(:'ticketTypeID', :'eventID', '{"title": "General admission"}');

-- Ticket type of the sibling event
select fx_event_ticket_type(:'otherTicketTypeID', :'eventOtherID', '{"title": "Other admission"}');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a purchase whose discount code belongs to its event
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                charge_model,
                currency_code,
                discount_amount_minor,
                event_discount_code_id,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id,

                discount_code
            ) values (
                900,
                'external',
                'USD',
                100,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                'pending',
                'General admission',
                %L::uuid,

                'OWN'
            )
        $$,
        :'discountCodeID',
        :'eventID',
        :'ticketTypeID',
        :'userDiscountAcceptedID'
    ),
    'Should accept a purchase whose discount code belongs to its event'
);

-- Should accept a purchase whose ticket type belongs to its event
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id
            ) values (
                0,
                %L::uuid,
                %L::uuid,
                'completed',
                'General admission',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'userTicketTypeAcceptedID'
    ),
    'Should accept a purchase whose ticket type belongs to its event'
);

-- Should reject a purchase whose discount code belongs to another event
select throws_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                charge_model,
                currency_code,
                discount_amount_minor,
                event_discount_code_id,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id,

                discount_code
            ) values (
                900,
                'external',
                'USD',
                100,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                'pending',
                'General admission',
                %L::uuid,

                'OTHER'
            )
        $$,
        :'otherDiscountCodeID',
        :'eventID',
        :'ticketTypeID',
        :'userDiscountRejectedID'
    ),
    '23503',
    'insert or update on table "event_purchase" violates foreign key constraint "event_purchase_event_discount_code_belongs_to_event_fkey"',
    'Should reject a purchase whose discount code belongs to another event'
);

-- Should reject a purchase whose ticket type belongs to another event
select throws_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id
            ) values (
                0,
                %L::uuid,
                %L::uuid,
                'completed',
                'Other admission',
                %L::uuid
            )
        $$,
        :'eventID',
        :'otherTicketTypeID',
        :'userTicketTypeRejectedID'
    ),
    '23503',
    'insert or update on table "event_purchase" violates foreign key constraint "event_purchase_event_ticket_type_belongs_to_event_fkey"',
    'Should reject a purchase whose ticket type belongs to another event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
