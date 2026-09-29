-- Tests admission offer deadline and price snapshot constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c0010000-0000-0000-0000-000000000001'
\set discountCodeID 'c0010000-0000-0000-0000-000000000002'
\set eventCategoryID 'c0010000-0000-0000-0000-000000000003'
\set eventID 'c0010000-0000-0000-0000-000000000004'
\set groupCategoryID 'c0010000-0000-0000-0000-000000000005'
\set groupID 'c0010000-0000-0000-0000-000000000006'
\set offerID 'c0010000-0000-0000-0000-000000000007'
\set priceWindowID 'c0010000-0000-0000-0000-000000000008'
\set ticketTypeID 'c0010000-0000-0000-0000-000000000009'
\set userID 'c0010000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Recipient
select fx_user(:'userID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Paid-capable event with a discount
select fx_event(:'eventID', :'groupID', :'eventCategoryID', '{"payment_currency_code": "USD"}');

-- Discount code covering the full ticket price
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    1000,
    'FREE',
    :'eventID',
    'fixed_amount',
    'Complimentary discount'
);

-- Ticket tier snapshotted by the offers
select fx_event_ticket_type(:'ticketTypeID', :'eventID', '{"title": "General admission"}');

-- Paid price window for the ticket tier
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', '{"amount_minor": 1000}');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow pending ticket offers before the first claim
select lives_ok(
    format(
        $$
            insert into admission_offer (
                admission_offer_id,
                event_id,
                event_ticket_type_id,
                expires_at,
                source,
                status,
                user_id
            ) values (
                %L::uuid,
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'approval',
                'pending',
                %L::uuid
            )
        $$,
        :'offerID',
        :'eventID',
        :'ticketTypeID',
        :'userID'
    ),
    'Should allow pending ticket offers before the first claim'
);

-- Should allow a pending offer to begin checkout after snapshotting its price
select lives_ok(
    format(
        $$
        update admission_offer
        set
            amount_minor = 1000,
            currency_code = 'USD',
            discount_amount_minor = 0,
            status = 'checkout_pending',
            ticket_title = 'General admission'
        where admission_offer_id = %L::uuid
        $$,
        :'offerID'
    ),
    'Should allow a pending offer to begin checkout after snapshotting its price'
);

-- Should allow organizers to cancel a checkout-pending offer
select lives_ok(
    format(
        $$
        update admission_offer
        set status = 'canceled'
        where admission_offer_id = %L::uuid
        $$,
        :'offerID'
    ),
    'Should allow organizers to cancel a checkout-pending offer'
);

-- Should allow intrinsic-free snapshots without currency
select lives_ok(
    format(
        $$
            insert into admission_offer (
                amount_minor,
                currency_code,
                discount_amount_minor,
                event_id,
                event_ticket_type_id,
                expires_at,
                source,
                status,
                ticket_title,
                user_id
            ) values (
                0,
                null,
                0,
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'organizer_invitation',
                'completed',
                'General admission',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'userID'
    ),
    'Should allow intrinsic-free snapshots without currency'
);

-- Should allow discounted-to-zero snapshots with currency and discount identity
select lives_ok(
    format(
        $$
            insert into admission_offer (
                amount_minor,
                currency_code,
                discount_amount_minor,
                discount_code,
                event_discount_code_id,
                event_id,
                event_ticket_type_id,
                expires_at,
                source,
                status,
                ticket_title,
                user_id
            ) values (
                0,
                'USD',
                1000,
                'FREE',
                %L::uuid,
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'organizer_invitation',
                'completed',
                'General admission',
                %L::uuid
            )
        $$,
        :'discountCodeID',
        :'eventID',
        :'ticketTypeID',
        :'userID'
    ),
    'Should allow discounted-to-zero snapshots with currency and discount identity'
);

-- Should reject null deadlines for every admission offer
select throws_ok(
    format(
        $$
            insert into admission_offer (
                event_id, event_ticket_type_id, expires_at, source, status, user_id
            ) values (
                %L::uuid,
                %L::uuid,
                null,
                'approval',
                'pending',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'userID'
    ),
    '23514',
    null,
    'Should reject null deadlines for every admission offer'
);

-- Should require deadlines after offer creation
select throws_ok(
    format(
        $$
            insert into admission_offer (
                created_at,
                event_id,
                event_ticket_type_id,
                expires_at,
                source,
                status,
                user_id
            ) values (
                current_timestamp,
                %L::uuid,
                %L::uuid,
                current_timestamp,
                'approval',
                'pending',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'userID'
    ),
    '23514',
    null,
    'Should require deadlines after offer creation'
);

-- Should reject partial ticket snapshots
select throws_ok(
    format(
        $$
            insert into admission_offer (
                event_id,
                event_ticket_type_id,
                expires_at,
                source,
                status,
                ticket_title,
                user_id
            ) values (
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'approval',
                'pending',
                'General admission',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'userID'
    ),
    '23514',
    null,
    'Should reject partial ticket snapshots'
);

-- Should reject currency on intrinsic-free snapshots
select throws_ok(
    format(
        $$
            insert into admission_offer (
                amount_minor,
                currency_code,
                discount_amount_minor,
                event_id,
                event_ticket_type_id,
                expires_at,
                source,
                status,
                ticket_title,
                user_id
            ) values (
                0,
                'USD',
                0,
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'approval',
                'completed',
                'General admission',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'userID'
    ),
    '23514',
    null,
    'Should reject currency on intrinsic-free snapshots'
);

-- Should require currency for discounted-to-zero snapshots
select throws_ok(
    format(
        $$
            insert into admission_offer (
                amount_minor,
                currency_code,
                discount_amount_minor,
                discount_code,
                event_discount_code_id,
                event_id,
                event_ticket_type_id,
                expires_at,
                source,
                status,
                ticket_title,
                user_id
            ) values (
                0,
                null,
                1000,
                'FREE',
                %L::uuid,
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'approval',
                'completed',
                'General admission',
                %L::uuid
            )
        $$,
        :'discountCodeID',
        :'eventID',
        :'ticketTypeID',
        :'userID'
    ),
    '23514',
    null,
    'Should require currency for discounted-to-zero snapshots'
);

-- Should reject discount identity without a positive discount amount
select throws_ok(
    format(
        $$
            insert into admission_offer (
                amount_minor,
                currency_code,
                discount_amount_minor,
                discount_code,
                event_discount_code_id,
                event_id,
                event_ticket_type_id,
                expires_at,
                source,
                status,
                ticket_title,
                user_id
            ) values (
                1000,
                'USD',
                0,
                'FREE',
                %L::uuid,
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'approval',
                'completed',
                'General admission',
                %L::uuid
            )
        $$,
        :'discountCodeID',
        :'eventID',
        :'ticketTypeID',
        :'userID'
    ),
    '23514',
    null,
    'Should reject discount identity without a positive discount amount'
);

-- Should require a snapshot before checkout begins
select throws_ok(
    format(
        $$
            insert into admission_offer (
                event_id, event_ticket_type_id, expires_at, source, status, user_id
            ) values (
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '1 hour',
                'approval',
                'checkout_pending',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'userID'
    ),
    '23514',
    null,
    'Should require a snapshot before checkout begins'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
