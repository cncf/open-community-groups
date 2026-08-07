-- Tests admission offer lifecycle and immutability guards.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set checkoutOfferID 'ab180000-0000-0000-0000-000000000001'
\set checkoutUserID 'ab180000-0000-0000-0000-000000000002'
\set communityID 'ab180000-0000-0000-0000-000000000003'
\set eventCategoryID 'ab180000-0000-0000-0000-000000000004'
\set eventID 'ab180000-0000-0000-0000-000000000005'
\set groupCategoryID 'ab180000-0000-0000-0000-000000000006'
\set groupID 'ab180000-0000-0000-0000-000000000007'
\set pendingOfferID 'ab180000-0000-0000-0000-000000000008'
\set pendingUserID 'ab180000-0000-0000-0000-000000000009'
\set replacementUserID 'ab180000-0000-0000-0000-00000000000a'
\set ticketTypeID 'ab180000-0000-0000-0000-00000000000b'

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
    'offer-lifecycle-community',
    'Offer Lifecycle Community',
    'Community for admission offer lifecycle tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category used by the lifecycle event
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
    'Offer Lifecycle Group',
    'offer-lifecycle-group'
);

-- Offer recipients
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'checkoutUserID', 'hash-checkout', 'checkout@example.test', true, 'checkout-user'),
    (:'pendingUserID', 'hash-pending', 'pending@example.test', true, 'pending-user'),
    (
        :'replacementUserID',
        'hash-replacement',
        'replacement@example.test',
        true,
        'replacement-user'
    );

-- Ticketed event
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
    'Event for admission offer lifecycle tests',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Offer Lifecycle Event',
    'USD',
    'offer-lifecycle-event',
    'UTC'
);

-- Ticket tier reserved by the lifecycle offers
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
    gen_random_uuid(),
    1000,
    :'ticketTypeID'
);

-- Pending and checkout-pending offers
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id,

    amount_minor,
    currency_code,
    discount_amount_minor,
    ticket_title
) values (
    :'pendingOfferID',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'approval',
    'pending',
    :'pendingUserID',

    null,
    null,
    null,
    null
), (
    :'checkoutOfferID',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'checkout_pending',
    :'checkoutUserID',

    1000,
    'USD',
    0,
    'General admission'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should finalize the first snapshot while an offer remains pending
select lives_ok(
    format(
        $$
            update admission_offer
            set
                amount_minor = 1000,
                currency_code = 'USD',
                discount_amount_minor = 0,
                ticket_title = 'General admission',
                updated_at = current_timestamp
            where admission_offer_id = %L::uuid
        $$,
        :'pendingOfferID'
    ),
    'Should finalize the first snapshot while an offer remains pending'
);

-- Should move a pending offer into checkout
select lives_ok(
    format(
        $$
            update admission_offer
            set status = 'checkout_pending', updated_at = current_timestamp
            where admission_offer_id = %L::uuid
        $$,
        :'pendingOfferID'
    ),
    'Should move a pending offer into checkout'
);

-- Should return an unexpired checkout offer to pending
select lives_ok(
    format(
        $$
            update admission_offer
            set status = 'pending', updated_at = current_timestamp
            where admission_offer_id = %L::uuid
        $$,
        :'pendingOfferID'
    ),
    'Should return an unexpired checkout offer to pending'
);

-- Should reject snapshot repricing
select throws_ok(
    format(
        $$
            update admission_offer
            set amount_minor = 900, updated_at = current_timestamp
            where admission_offer_id = %L::uuid
        $$,
        :'pendingOfferID'
    ),
    'admission offer price snapshot is immutable',
    'Should reject snapshot repricing'
);

-- Should allow a pending offer to be declined
select lives_ok(
    format(
        $$
            update admission_offer
            set status = 'declined', updated_at = current_timestamp
            where admission_offer_id = %L::uuid
        $$,
        :'pendingOfferID'
    ),
    'Should allow a pending offer to be declined'
);

-- Should reject reviving a declined offer
select throws_ok(
    format(
        $$
            update admission_offer
            set status = 'pending', updated_at = current_timestamp
            where admission_offer_id = %L::uuid
        $$,
        :'pendingOfferID'
    ),
    'invalid admission offer status transition: declined -> pending',
    'Should reject reviving a declined offer'
);

-- Should reject transferring an offer
select throws_ok(
    format(
        $$
            update admission_offer
            set user_id = %L::uuid, updated_at = current_timestamp
            where admission_offer_id = %L::uuid
        $$,
        :'replacementUserID',
        :'pendingOfferID'
    ),
    'admission offer ownership and deadline fields are immutable',
    'Should reject transferring an offer'
);

-- Should allow canceling an offer while checkout is pending
select lives_ok(
    format(
        $$
            update admission_offer
            set status = 'canceled', updated_at = current_timestamp
            where admission_offer_id = %L::uuid
        $$,
        :'checkoutOfferID'
    ),
    'Should allow canceling an offer while checkout is pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
