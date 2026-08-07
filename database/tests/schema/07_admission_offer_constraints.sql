-- Tests admission offer deadline and price snapshot invariants.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a010000-0000-0000-0000-000000000001'
\set discountCodeID '7a010000-0000-0000-0000-000000000002'
\set eventCategoryID '7a010000-0000-0000-0000-000000000003'
\set eventID '7a010000-0000-0000-0000-000000000004'
\set groupCategoryID '7a010000-0000-0000-0000-000000000005'
\set groupID '7a010000-0000-0000-0000-000000000006'
\set offerID '7a010000-0000-0000-0000-00000000000a'
\set priceWindowID '7a010000-0000-0000-0000-000000000007'
\set ticketTypeID '7a010000-0000-0000-0000-000000000008'
\set userID '7a010000-0000-0000-0000-000000000009'

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
    'offer-constraint-community',
    'Offer Constraint Community',
    'Community for admission offer constraint tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Offer Constraint Group',
    'offer-constraint-group'
);

-- Recipient
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'hash-user', 'offer@example.test', true, 'offer-user');

-- Paid-capable event with a discount
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    slug,
    timezone
) values (
    :'eventID',
    'Event for admission offer constraints',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Offer Constraint Event',
    'USD',
    'offer-constraint-event',
    'UTC'
);

-- Ticket tier snapshotted by the offers
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeID',
    :'eventID',
    1,
    10,
    'General admission'
);

-- Paid price window for the ticket tier
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    1000,
    :'ticketTypeID'
);

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
