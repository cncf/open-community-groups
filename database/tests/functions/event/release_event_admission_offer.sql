-- Tests releasing active admission offers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a140000-0000-0000-0000-000000000001'
\set discountCodeID '4a140000-0000-0000-0000-000000000002'
\set eventCategoryID '4a140000-0000-0000-0000-000000000003'
\set eventID '4a140000-0000-0000-0000-000000000004'
\set expiredOfferID '4a140000-0000-0000-0000-000000000011'
\set groupCategoryID '4a140000-0000-0000-0000-000000000005'
\set groupID '4a140000-0000-0000-0000-000000000006'
\set missingOfferID '4a140000-0000-0000-0000-000000000012'
\set offerID '4a140000-0000-0000-0000-000000000007'
\set offerUserID '4a140000-0000-0000-0000-000000000008'
\set otherGroupID '4a140000-0000-0000-0000-000000000013'
\set otherUserID '4a140000-0000-0000-0000-000000000014'
\set priceWindowID '4a140000-0000-0000-0000-000000000009'
\set purchaseID '4a140000-0000-0000-0000-00000000000a'
\set queueUserID '4a140000-0000-0000-0000-00000000000b'
\set rsvpEventID '4a140000-0000-0000-0000-00000000000d'
\set rsvpSweepActiveOfferID '4a140000-0000-0000-0000-000000000015'
\set rsvpSweepActiveOfferUserID '4a140000-0000-0000-0000-000000000016'
\set rsvpSweepEventID '4a140000-0000-0000-0000-000000000017'
\set rsvpSweepExpiredOfferID '4a140000-0000-0000-0000-000000000018'
\set rsvpSweepExpiredOfferUserID '4a140000-0000-0000-0000-000000000019'
\set rsvpSweepFinalQueueUserID '4a140000-0000-0000-0000-00000000001a'
\set rsvpSweepFirstQueueUserID '4a140000-0000-0000-0000-00000000001b'
\set rsvpOfferID '4a140000-0000-0000-0000-00000000000e'
\set rsvpOfferUserID '4a140000-0000-0000-0000-00000000000f'
\set rsvpQueueUserID '4a140000-0000-0000-0000-000000000010'
\set ticketTypeID '4a140000-0000-0000-0000-00000000000c'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    :'communityID',
    'Admission offer release tests',
    'Offer Release Community',
    'https://example.com/logo.png',
    'offer-release-community'
);

-- Group category
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Technology');

-- Event category
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'General');

-- Users holding or queued behind ticketed and RSVP offers
insert into "user" (auth_hash, email, email_verified, user_id, username)
values
    ('hash-offer', 'offer@example.com', true, :'offerUserID', 'offer-user'),
    ('hash-queue', 'queue@example.com', true, :'queueUserID', 'queue-user'),
    ('hash-rsvp-offer', 'rsvp-offer@example.com', true, :'rsvpOfferUserID', 'rsvp-offer'),
    ('hash-rsvp-queue', 'rsvp-queue@example.com', true, :'rsvpQueueUserID', 'rsvp-queue');

-- Users used by RSVP pre-release reconciliation promotion coverage
insert into "user" (auth_hash, email, email_verified, user_id, username)
values
    (
        'hash-rsvp-sweep-active-offer',
        'rsvp-sweep-active-offer@example.com',
        true,
        :'rsvpSweepActiveOfferUserID',
        'rsvp-sweep-active-offer'
    ),
    (
        'hash-rsvp-sweep-expired-offer',
        'rsvp-sweep-expired-offer@example.com',
        true,
        :'rsvpSweepExpiredOfferUserID',
        'rsvp-sweep-expired-offer'
    ),
    (
        'hash-rsvp-sweep-final-queue',
        'rsvp-sweep-final-queue@example.com',
        true,
        :'rsvpSweepFinalQueueUserID',
        'rsvp-sweep-final-queue'
    ),
    (
        'hash-rsvp-sweep-first-queue',
        'rsvp-sweep-first-queue@example.com',
        true,
        :'rsvpSweepFirstQueueUserID',
        'rsvp-sweep-first-queue'
    );

-- Payment-ready group
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    payment_recipient,
    slug
) values (
    :'communityID',
    :'groupCategoryID',
    :'groupID',
    'Offer Release Group',
    '{"provider":"stripe","recipient_id":"acct_release"}'::jsonb,
    'offer-release-group'
);

-- Published ticketed event and its single public seat
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    timezone
) values (
    'Admission offer release event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Offer Release Event',
    'USD',
    true,
    'offer-release-event',
    current_timestamp + interval '1 day',
    'UTC'
);

-- Published RSVP event whose released offer opens one waitlist seat
insert into event (
    capacity,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone,
    waitlist_enabled
) values (
    1,
    'RSVP offer release event',
    :'eventCategoryID',
    :'rsvpEventID',
    'in-person',
    :'groupID',
    'RSVP Offer Release Event',
    true,
    'rsvp-offer-release-event',
    current_timestamp + interval '1 day',
    'UTC',
    true
);

-- Published RSVP event whose pre-release sweep and final release each open a seat
insert into event (
    capacity,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone,
    waitlist_enabled
) values (
    2,
    'RSVP pre-release sweep event',
    :'eventCategoryID',
    :'rsvpSweepEventID',
    'in-person',
    :'groupID',
    'RSVP Sweep Release Event',
    true,
    'rsvp-sweep-release-event',
    current_timestamp + interval '1 day',
    'UTC',
    true
);

-- Single public paid seat on the ticketed event
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    :'eventID',
    :'ticketTypeID',
    1,
    1,
    'General admission'
);

-- Paid price window for the ticketed seat
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values (
    2500,
    :'priceWindowID',
    :'ticketTypeID'
);

-- Discount code reserved by the checkout-pending offer
insert into event_discount_code (
    active,
    amount_minor,
    available,
    available_override_active,
    code,
    event_discount_code_id,
    event_id,
    kind,
    title
) values (
    true,
    500,
    1,
    true,
    'SAVE500',
    :'discountCodeID',
    :'eventID',
    'fixed_amount',
    'Save 500'
);

-- Checkout-pending offer snapshotting the discounted price
insert into admission_offer (
    admission_offer_id,
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
    :'offerID',
    2000,
    'USD',
    500,
    'SAVE500',
    :'discountCodeID',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'checkout_pending',
    'General admission',
    :'offerUserID'
);

-- Pending purchase holding the offer's checkout
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'offerID',
    2000,
    'USD',
    500,
    'SAVE500',
    :'discountCodeID',
    :'eventID',
    :'purchaseID',
    :'ticketTypeID',
    current_timestamp + interval '15 minutes',
    'pending',
    'General admission',
    :'offerUserID'
);

-- In-progress attendee row tied to the checkout-pending offer
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'registration-questions-pending', :'offerUserID');

-- Ticketed queue head promoted when the offer is released
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'eventID', :'ticketTypeID', :'queueUserID');

-- Active RSVP offer reserving the event's only seat
insert into admission_offer (
    admission_offer_id,
    event_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'rsvpOfferID',
    :'rsvpEventID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'rsvpOfferUserID'
);

-- RSVP queue head promoted when the active offer is released
insert into event_waitlist (event_id, user_id)
values (:'rsvpEventID', :'rsvpQueueUserID');

-- Active RSVP offer released after the pre-release sweep
insert into admission_offer (
    admission_offer_id,
    event_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'rsvpSweepActiveOfferID',
    :'rsvpSweepEventID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'rsvpSweepActiveOfferUserID'
);

-- Expired RSVP offer swept before the selected offer is released
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'rsvpSweepExpiredOfferID',
    current_timestamp - interval '2 hours',
    :'rsvpSweepEventID',
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'pending',
    :'rsvpSweepExpiredOfferUserID'
);

-- RSVP queue entries promoted by the pre-release sweep and final release
insert into event_waitlist (created_at, event_id, user_id)
values
    (
        current_timestamp - interval '10 minutes',
        :'rsvpSweepEventID',
        :'rsvpSweepFirstQueueUserID'
    ),
    (
        current_timestamp - interval '5 minutes',
        :'rsvpSweepEventID',
        :'rsvpSweepFinalQueueUserID'
    );

-- Expired offer used by unavailable guard coverage
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'expiredOfferID',
    current_timestamp - interval '2 hours',
    :'eventID',
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'expired',
    :'offerUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject an invalid terminal status
select throws_ok(
    format(
        $$
            select release_event_admission_offer(
                %L::uuid,
                'completed',
                null,
                null,
                null
            )
        $$,
        :'offerID'
    ),
    'invalid admission offer release status',
    'Should reject an invalid terminal status'
);

-- Should reject a missing admission offer
select throws_ok(
    format(
        $$
            select release_event_admission_offer(
                %L::uuid,
                'canceled',
                null,
                null,
                null
            )
        $$,
        :'missingOfferID'
    ),
    'admission offer is no longer available',
    'Should reject a missing admission offer'
);

-- Should reject a non-active admission offer
select throws_ok(
    format(
        $$
            select release_event_admission_offer(
                %L::uuid,
                'canceled',
                null,
                null,
                null
            )
        $$,
        :'expiredOfferID'
    ),
    'admission offer is no longer available',
    'Should reject a non-active admission offer'
);

-- Should reject an unexpected group
select throws_ok(
    format(
        $$
            select release_event_admission_offer(
                %L::uuid,
                'canceled',
                %L::uuid,
                null,
                null
            )
        $$,
        :'offerID',
        :'otherGroupID'
    ),
    'admission offer is no longer available',
    'Should reject an unexpected group'
);

-- Should reject an unexpected user
select throws_ok(
    format(
        $$
            select release_event_admission_offer(
                %L::uuid,
                'canceled',
                null,
                %L::uuid,
                null
            )
        $$,
        :'offerID',
        :'otherUserID'
    ),
    'admission offer is no longer available',
    'Should reject an unexpected user'
);

-- Should return released offer context
select results_eq(
    format(
        $$
        select
            community_id,
            event_id,
            event_ticket_type_id,
            group_id,
            promoted_user_ids,
            source,
            user_id
        from release_event_admission_offer(
            %L::uuid,
            'canceled',
            %L::uuid,
            null,
            'stripe'
        )
        $$,
        :'offerID',
        :'groupID'
    ),
    format(
        $$
        values (
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            array[]::uuid[],
            'organizer_invitation'::text,
            %L::uuid
        )
        $$,
        :'communityID',
        :'eventID',
        :'ticketTypeID',
        :'groupID',
        :'offerUserID'
    ),
    'Should return released offer context'
);

-- Should return RSVP users promoted after an offer release
select results_eq(
    format(
        $$
            select
                event_id,
                promoted_user_ids
            from release_event_admission_offer(
                %L::uuid,
                'declined',
                null,
                %L::uuid,
                null
            )
        $$,
        :'rsvpOfferID',
        :'rsvpOfferUserID'
    ),
    format(
        $$
            values (
                %L::uuid,
                array[%L::uuid]
            )
        $$,
        :'rsvpEventID',
        :'rsvpQueueUserID'
    ),
    'Should return RSVP users promoted after an offer release'
);

-- Should persist the RSVP promotion before returning
select results_eq(
    format(
        $$
            select
                ao.status,
                ea.status,
                not exists (
                    select 1
                    from event_waitlist ew
                    where ew.event_id = %L::uuid
                    and ew.user_id = %L::uuid
                )
            from admission_offer ao
            join event_attendee ea
                on ea.event_id = ao.event_id
                and ea.user_id = %L::uuid
            where ao.admission_offer_id = %L::uuid
        $$,
        :'rsvpEventID',
        :'rsvpQueueUserID',
        :'rsvpQueueUserID',
        :'rsvpOfferID'
    ),
    $$ values ('declined'::text, 'confirmed'::text, true) $$,
    'Should persist the RSVP promotion before returning'
);

-- Should return RSVP users promoted before and after an offer release
select results_eq(
    format(
        $$
            select
                event_id,
                promoted_user_ids
            from release_event_admission_offer(
                %L::uuid,
                'declined',
                null,
                %L::uuid,
                null
            )
        $$,
        :'rsvpSweepActiveOfferID',
        :'rsvpSweepActiveOfferUserID'
    ),
    format(
        $$
            values (
                %L::uuid,
                array[%L::uuid, %L::uuid]
            )
        $$,
        :'rsvpSweepEventID',
        :'rsvpSweepFirstQueueUserID',
        :'rsvpSweepFinalQueueUserID'
    ),
    'Should return RSVP users promoted before and after an offer release'
);

-- Should persist RSVP pre-release and final promotion state
select is(
    (
        select jsonb_build_object(
            'active_offer_status', (
                select ao.status
                from admission_offer ao
                where ao.admission_offer_id = :'rsvpSweepActiveOfferID'::uuid
            ),
            'expired_offer_status', (
                select ao.status
                from admission_offer ao
                where ao.admission_offer_id = :'rsvpSweepExpiredOfferID'::uuid
            ),
            'promoted_count', (
                select count(*)::int
                from event_attendee ea
                where ea.event_id = :'rsvpSweepEventID'::uuid
                and ea.status = 'confirmed'
                and ea.user_id in (
                    :'rsvpSweepFirstQueueUserID'::uuid,
                    :'rsvpSweepFinalQueueUserID'::uuid
                )
            ),
            'waitlist_count', (
                select count(*)::int
                from event_waitlist ew
                where ew.event_id = :'rsvpSweepEventID'::uuid
            )
        )
    ),
    '{
        "active_offer_status": "declined",
        "expired_offer_status": "expired",
        "promoted_count": 2,
        "waitlist_count": 0
    }'::jsonb,
    'Should persist RSVP pre-release and final promotion state'
);

-- Should release checkout, discount, and pending attendee state
select results_eq(
    format(
        $$
        select
            ao.status,
            ep.status,
            edc.available,
            exists (
                select 1
                from event_attendee ea
                where ea.event_id = %L::uuid
                and ea.user_id = %L::uuid
            )
        from admission_offer ao
        join event_purchase ep using (admission_offer_id)
        join event_discount_code edc
            on edc.event_discount_code_id = ep.event_discount_code_id
        where ao.admission_offer_id = %L::uuid
        $$,
        :'eventID',
        :'offerUserID',
        :'offerID'
    ),
    $$ values ('canceled'::text, 'expired'::text, 2, false) $$,
    'Should release checkout, discount, and pending attendee state'
);

-- Should promote the next queued user after releasing capacity
select results_eq(
    format(
        $$
        select ao.source, ao.status
        from admission_offer ao
        where ao.event_id = %L::uuid
        and ao.user_id = %L::uuid
        $$,
        :'eventID',
        :'queueUserID'
    ),
    $$ values ('waitlist'::text, 'pending'::text) $$,
    'Should promote the next queued user after releasing capacity'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
