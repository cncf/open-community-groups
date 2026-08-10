-- Tests closing active event enrollment reservations and queues.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '4a170000-0000-0000-0000-000000000001'
\set checkoutOfferID '4a170000-0000-0000-0000-000000000002'
\set checkoutPurchaseID '4a170000-0000-0000-0000-000000000003'
\set checkoutUserID '4a170000-0000-0000-0000-000000000004'
\set communityID '4a170000-0000-0000-0000-000000000005'
\set confirmedPurchaseID '4a170000-0000-0000-0000-000000000015'
\set confirmedUserID '4a170000-0000-0000-0000-000000000016'
\set directPurchaseID '4a170000-0000-0000-0000-000000000006'
\set directUserID '4a170000-0000-0000-0000-000000000007'
\set discountCodeID '4a170000-0000-0000-0000-000000000008'
\set eventCategoryID '4a170000-0000-0000-0000-000000000009'
\set groupCategoryID '4a170000-0000-0000-0000-00000000000a'
\set groupID '4a170000-0000-0000-0000-00000000000b'
\set offerID '4a170000-0000-0000-0000-00000000000c'
\set offerUserID '4a170000-0000-0000-0000-00000000000d'
\set priceWindowID '4a170000-0000-0000-0000-00000000000e'
\set queueEventID '4a170000-0000-0000-0000-00000000000f'
\set queueTicketTypeID '4a170000-0000-0000-0000-000000000010'
\set requestEventID '4a170000-0000-0000-0000-000000000011'
\set requestTicketTypeID '4a170000-0000-0000-0000-000000000012'
\set requestUserID '4a170000-0000-0000-0000-000000000013'
\set waitlistUserID '4a170000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns both enrollment closure scenarios
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    'https://example.test/banner-mobile.png',
    'https://example.test/banner.png',
    'Community for enrollment closure tests',
    'Enrollment Closure Community',
    'https://example.test/logo.png',
    'enrollment-closure-community'
);

-- Event category used by both enrollment closure scenarios
insert into event_category (
    event_category_id,
    community_id,
    name
) values (
    :'eventCategoryID',
    :'communityID',
    'Meetup'
);

-- Group category used by the enrollment closure group
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    :'groupCategoryID',
    :'communityID',
    'Technology'
);

-- Group that owns both enrollment closure events
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    payment_recipient,
    slug
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Enrollment Closure Group',
    '{"provider": "stripe", "recipient_id": "acct_close", "seller_display_name": "Close Event Fiscal Sponsor"}'::jsonb,
    'enrollment-closure-group'
);

-- Users participating in the enrollment closure scenarios
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username
) values
    (
        :'actorUserID',
        'hash-actor',
        'actor@example.test',
        true,
        'close-actor'
    ),
    (
        :'checkoutUserID',
        'hash-checkout',
        'checkout@example.test',
        true,
        'close-checkout'
    ),
    (
        :'confirmedUserID',
        'hash-confirmed',
        'confirmed@example.test',
        true,
        'close-confirmed'
    ),
    (
        :'directUserID',
        'hash-direct',
        'direct@example.test',
        true,
        'close-direct'
    ),
    (
        :'offerUserID',
        'hash-offer',
        'offer@example.test',
        true,
        'close-offer'
    ),
    (
        :'requestUserID',
        'hash-request',
        'request@example.test',
        true,
        'close-request'
    ),
    (
        :'waitlistUserID',
        'hash-waitlist',
        'waitlist@example.test',
        true,
        'close-waitlist'
    );

-- Ticketed waitlist event with active offers and checkouts
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    timezone,
    waitlist_enabled
) values (
    :'queueEventID',
    'Event with active enrollment reservations',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Queue Closure Event',
    'USD',
    true,
    'queue-closure-event',
    current_timestamp + interval '2 days',
    'UTC',
    true
);

-- Approval event with a pending ticket request
insert into event (
    event_id,
    attendee_approval_required,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    timezone
) values (
    :'requestEventID',
    true,
    'Event with a pending approval request',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Request Closure Event',
    'USD',
    true,
    'request-closure-event',
    current_timestamp + interval '2 days',
    'UTC'
);

-- Ticket tiers used by the queue and request events
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values
    (
        :'queueTicketTypeID',
        :'queueEventID',
        1,
        10,
        'Queue admission'
    ),
    (
        :'requestTicketTypeID',
        :'requestEventID',
        1,
        10,
        'Request admission'
    );

-- Current price used by the active checkout snapshots
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    1000,
    :'queueTicketTypeID'
);

-- Discount reserved by both active checkout purchases
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    500,
    0,
    true,
    'CLOSE5',
    :'queueEventID',
    'fixed_amount',
    'Closure discount'
);

-- Active pending and checkout-pending admission offers
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
    discount_code,
    event_discount_code_id,
    ticket_title
) values
    (
        :'checkoutOfferID',
        :'queueEventID',
        :'queueTicketTypeID',
        current_timestamp + interval '1 hour',
        'approval',
        'checkout_pending',
        :'checkoutUserID',

        500,
        'USD',
        500,
        'CLOSE5',
        :'discountCodeID',
        'Queue admission'
    ),
    (
        :'offerID',
        :'queueEventID',
        :'queueTicketTypeID',
        current_timestamp + interval '1 hour',
        'waitlist',
        'pending',
        :'offerUserID',

        null,
        null,
        null,
        null,
        null,
        null
    );

-- Offer-linked and direct pending checkout purchases
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
) values
    (
        :'checkoutOfferID',
        0,
        'USD',
        500,
        'CLOSE5',
        :'discountCodeID',
        :'queueEventID',
        :'checkoutPurchaseID',
        :'queueTicketTypeID',
        current_timestamp + interval '15 minutes',
        'pending',
        'Queue admission',
        :'checkoutUserID'
    ),
    (
        null,
        0,
        'USD',
        500,
        'CLOSE5',
        :'discountCodeID',
        :'queueEventID',
        :'directPurchaseID',
        :'queueTicketTypeID',
        current_timestamp + interval '15 minutes',
        'pending',
        'Queue admission',
        :'directUserID'
    );

-- Completed purchase preserved when enrollment closes
insert into event_purchase (
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    0,
    :'queueEventID',
    :'confirmedPurchaseID',
    :'queueTicketTypeID',
    'completed',
    'Queue admission',
    :'confirmedUserID'
);

-- Checkout-created attendee holds released when pending purchases expire
insert into event_attendee (
    event_id,
    status,
    user_id
) values
    (
        :'queueEventID',
        'registration-questions-pending',
        :'checkoutUserID'
    ),
    (
        :'queueEventID',
        'registration-questions-pending',
        :'directUserID'
    );

-- Confirmed attendee preserved when enrollment closes
insert into event_attendee (
    event_id,
    status,
    user_id
) values (
    :'queueEventID',
    'confirmed',
    :'confirmedUserID'
);

-- FIFO queue cleared when enrollment closes
insert into event_waitlist (
    event_id,
    event_ticket_type_id,
    user_id
) values (
    :'queueEventID',
    :'queueTicketTypeID',
    :'waitlistUserID'
);

-- Pending approval request cleared when enrollment closes
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    status,
    user_id
) values (
    :'requestEventID',
    :'requestTicketTypeID',
    'pending',
    :'requestUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel active offers and clear checkout and queue reservations
select is(
    close_event_enrollment(:'actorUserID', :'queueEventID'),
    array[:'checkoutUserID'::uuid, :'offerUserID'::uuid],
    'Should cancel active offers and clear checkout and queue reservations'
);

select results_eq(
    format(
        $$
            select
                (
                    select array_agg(status order by admission_offer_id)
                    from admission_offer
                    where event_id = %L::uuid
                ),
                (
                    select array_agg(status order by event_purchase_id)
                    from event_purchase
                    where event_id = %L::uuid
                ),
                (
                    select available
                    from event_discount_code
                    where event_discount_code_id = %L::uuid
                ),
                (
                    select count(*)
                    from event_attendee
                    where event_id = %L::uuid
                    and status = 'registration-questions-pending'
                ),
                (
                    select count(*)
                    from event_waitlist
                    where event_id = %L::uuid
                )
        $$,
        :'queueEventID',
        :'queueEventID',
        :'discountCodeID',
        :'queueEventID',
        :'queueEventID'
    ),
    $$ values (
        array['canceled', 'canceled']::text[],
        array['expired', 'expired', 'completed']::text[],
        2,
        0::bigint,
        0::bigint
    ) $$,
    'Should expire checkouts, release discounts and attendee holds, and clear the queue'
);

-- Should preserve confirmed attendees and completed purchases
select results_eq(
    format(
        $$
            select
                ea.status,
                ep.status
            from event_attendee ea
            join event_purchase ep
                on ep.event_id = ea.event_id
                and ep.user_id = ea.user_id
            where ea.event_id = %L::uuid
            and ea.user_id = %L::uuid
            and ep.event_purchase_id = %L::uuid
        $$,
        :'queueEventID',
        :'confirmedUserID',
        :'confirmedPurchaseID'
    ),
    $$ values ('confirmed'::text, 'completed'::text) $$,
    'Should preserve confirmed attendees and completed purchases'
);

select is(
    (
        select count(*)::int
        from audit_log
        where event_id = :'queueEventID'::uuid
        and action = 'admission_offer_canceled'
    ),
    2,
    'Should audit each canceled admission offer'
);

select is(
    (
        select count(*)::int
        from notification
        where kind = 'event-admission-offer-canceled'
        and user_id in (:'checkoutUserID'::uuid, :'offerUserID'::uuid)
    ),
    2,
    'Should enqueue one cancellation notification per canceled offer'
);

-- Should clear pending approval requests
select is(
    close_event_enrollment(:'actorUserID', :'requestEventID'),
    array[]::uuid[],
    'Should close an event that only has pending approval requests'
);

select is(
    (
        select count(*)::int
        from event_invitation_request
        where event_id = :'requestEventID'::uuid
    ),
    0,
    'Should clear pending approval requests'
);

-- Should remain idempotent after enrollment is already closed
select is(
    close_event_enrollment(:'actorUserID', :'queueEventID'),
    array[]::uuid[],
    'Should remain idempotent after enrollment is already closed'
);

-- Should reject a missing event
select throws_ok(
    $$select close_event_enrollment(
        '4a170000-0000-0000-0000-000000000001'::uuid,
        '4a170000-0000-0000-0000-000000000099'::uuid
    )$$,
    'event not found',
    'Should reject a missing event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
