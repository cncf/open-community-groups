-- Tests admission offer lifecycle and immutability guards.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set checkoutOfferID 'ab180000-0000-0000-0000-000000000001'
\set checkoutUserID 'ab180000-0000-0000-0000-000000000002'
\set claimOverwriteOfferID 'ab180000-0000-0000-0000-00000000000c'
\set claimOverwriteUserID 'ab180000-0000-0000-0000-00000000000d'
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

-- Baseline community, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'claimOverwriteUserID');
select fx_user(:'checkoutUserID');
select fx_user(:'pendingUserID');
select fx_user(:'replacementUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Ticketed event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));

-- Ticket tier reserved by the lifecycle offers
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Paid price window for the ticket tier
select fx_event_ticket_price_window(gen_random_uuid(), :'ticketTypeID', jsonb_build_object('amount_minor', 1000));

-- Pending, snapshotted-pending, and checkout-pending offers
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
), (
    :'claimOverwriteOfferID',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'approval',
    'pending',
    :'claimOverwriteUserID',

    1000,
    'USD',
    0,
    'General admission'
), (
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

-- Should allow a snapshotted pending offer to be claimed at a new price
select lives_ok(
    format(
        $$
            update admission_offer
            set
                amount_minor = 500,
                currency_code = 'USD',
                discount_amount_minor = 0,
                status = 'checkout_pending',
                ticket_title = 'General admission',
                updated_at = current_timestamp
            where admission_offer_id = %L::uuid
        $$,
        :'claimOverwriteOfferID'
    ),
    'Should allow a snapshotted pending offer to be claimed at a new price'
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

-- Should allow extending a checkout-pending offer deadline
select lives_ok(
    format(
        $$
            update admission_offer
            set expires_at = current_timestamp + interval '2 hours',
                updated_at = current_timestamp
            where admission_offer_id = %L::uuid
        $$,
        :'checkoutOfferID'
    ),
    'Should allow extending a checkout-pending offer deadline'
);

-- Should reject shortening a checkout-pending offer deadline
select throws_ok(
    format(
        $$
            update admission_offer
            set expires_at = current_timestamp + interval '1 minute',
                updated_at = current_timestamp
            where admission_offer_id = %L::uuid
        $$,
        :'checkoutOfferID'
    ),
    'admission offer ownership and deadline fields are immutable',
    'Should reject shortening a checkout-pending offer deadline'
);

-- Should reject snapshot repricing after checkout has started
select throws_ok(
    format(
        $$
            update admission_offer
            set amount_minor = 900, updated_at = current_timestamp
            where admission_offer_id = %L::uuid
        $$,
        :'checkoutOfferID'
    ),
    'admission offer price snapshot is immutable',
    'Should reject snapshot repricing after checkout has started'
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
