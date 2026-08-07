-- Tests purchase writes while admission offers reserve enrollment.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeOfferID 'ab160000-0000-0000-0000-000000000001'
\set activeOfferUserID 'ab160000-0000-0000-0000-000000000002'
\set communityID 'ab160000-0000-0000-0000-000000000003'
\set eventCategoryID 'ab160000-0000-0000-0000-000000000004'
\set eventID 'ab160000-0000-0000-0000-000000000005'
\set groupCategoryID 'ab160000-0000-0000-0000-000000000006'
\set groupID 'ab160000-0000-0000-0000-000000000007'
\set refundPurchaseID 'ab160000-0000-0000-0000-000000000010'
\set terminalOfferUserID 'ab160000-0000-0000-0000-000000000008'
\set ticketTypeID 'ab160000-0000-0000-0000-000000000009'

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
    'purchase-offer-community',
    'Purchase Offer Community',
    'Community for offer purchase trigger tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category used by the purchase event
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category used by the hosting group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Purchase Offer Group',
    'purchase-offer-group'
);

-- Offer recipients
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (
        :'activeOfferUserID',
        'hash-active-offer',
        'active-offer@example.test',
        true,
        'active-offer-user'
    ),
    (
        :'terminalOfferUserID',
        'hash-terminal-offer',
        'terminal-offer@example.test',
        true,
        'terminal-offer-user'
    );

-- Ticketed event
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    :'eventID',
    'Event for purchase offer trigger tests',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Purchase Offer Event',
    'purchase-offer-event',
    'UTC'
);

-- Ticket tier purchased in the trigger scenarios
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

-- Active and terminal offers
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'activeOfferID',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'activeOfferUserID'
), (
    gen_random_uuid(),
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'canceled',
    :'terminalOfferUserID'
);

-- Expired direct purchase that may receive a delayed provider payment
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'refundPurchaseID',
    0,
    null,
    :'eventID',
    :'ticketTypeID',
    'expired',
    'General admission',
    :'activeOfferUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject direct active purchases while an offer is active
select throws_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                currency_code,
                event_id,
                event_ticket_type_id,
                hold_expires_at,
                status,
                ticket_title,
                user_id
            ) values (
                0,
                null,
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '10 minutes',
                'pending',
                'General admission',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'activeOfferUserID'
    ),
    'active admission offer must be claimed directly',
    'Should reject direct purchases while an offer is active'
);

-- Should allow purchases explicitly linked to the active offer
select lives_ok(
    format(
        $$
            insert into event_purchase (
                admission_offer_id,
                amount_minor,
                currency_code,
                event_id,
                event_ticket_type_id,
                hold_expires_at,
                status,
                ticket_title,
                user_id
            ) values (
                %L::uuid,
                0,
                null,
                %L::uuid,
                %L::uuid,
                current_timestamp + interval '10 minutes',
                'pending',
                'General admission',
                %L::uuid
            )
        $$,
        :'activeOfferID',
        :'eventID',
        :'ticketTypeID',
        :'activeOfferUserID'
    ),
    'Should allow purchases linked to their active offer'
);

-- Should ignore historical purchases that do not reserve inventory
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                currency_code,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id
            ) values (
                0,
                null,
                %L::uuid,
                %L::uuid,
                'expired',
                'General admission',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'activeOfferUserID'
    ),
    'Should allow historical direct purchases while an offer is active'
);

-- Should allow an expired direct purchase to enter refund processing
select lives_ok(
    format(
        $$
            update event_purchase
            set status = 'refund-pending'
            where event_purchase_id = %L::uuid
        $$,
        :'refundPurchaseID'
    ),
    'Should allow an expired direct purchase to enter refund processing'
);

select results_eq(
    format(
        $$
            select status
            from event_purchase
            where event_purchase_id = %L::uuid
        $$,
        :'refundPurchaseID'
    ),
    $$ values ('refund-pending'::text) $$,
    'Should persist the refund-pending purchase beside the active offer'
);

-- Should allow refund processing to enter recovery
select lives_ok(
    format(
        $$
            update event_purchase
            set status = 'refund-recovery-pending'
            where event_purchase_id = %L::uuid
        $$,
        :'refundPurchaseID'
    ),
    'Should allow refund processing to enter recovery'
);

select results_eq(
    format(
        $$
            select status
            from event_purchase
            where event_purchase_id = %L::uuid
        $$,
        :'refundPurchaseID'
    ),
    $$ values ('refund-recovery-pending'::text) $$,
    'Should persist refund recovery beside the active offer'
);

-- Should allow direct active purchases after the offer is terminal
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                currency_code,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id
            ) values (
                0,
                null,
                %L::uuid,
                %L::uuid,
                'completed',
                'General admission',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'terminalOfferUserID'
    ),
    'Should allow direct active purchases after a terminal offer'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
