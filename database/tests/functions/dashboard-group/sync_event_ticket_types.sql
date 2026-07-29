-- Tests synchronizing event ticket types and price windows.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(19);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a350000-0000-0000-0000-000000000001'
\set eventCategoryID '3a350000-0000-0000-0000-000000000002'
\set eventExpiredOffersID '3a350000-0000-0000-0000-000000000022'
\set eventID '3a350000-0000-0000-0000-000000000003'
\set eventGuardedID '3a350000-0000-0000-0000-000000000018'
\set eventProtectedID '3a350000-0000-0000-0000-000000000004'
\set eventRequestedID '3a350000-0000-0000-0000-00000000001d'
\set eventWaitlistRemovalID '3a350000-0000-0000-0000-000000000020'
\set groupCategoryID '3a350000-0000-0000-0000-000000000005'
\set groupID '3a350000-0000-0000-0000-000000000006'
\set ticketType1ID '3a350000-0000-0000-0000-000000000007'
\set ticketType2ID '3a350000-0000-0000-0000-000000000008'
\set ticketType3ID '3a350000-0000-0000-0000-000000000009'
\set ticketTypeExpiredOffersID '3a350000-0000-0000-0000-000000000023'
\set ticketTypeGuardedID '3a350000-0000-0000-0000-000000000019'
\set ticketTypeProtectedID '3a350000-0000-0000-0000-000000000010'
\set ticketTypeRequestedID '3a350000-0000-0000-0000-00000000001e'
\set ticketTypeWaitlistRemovalID '3a350000-0000-0000-0000-000000000021'
\set offerGuardedID '3a350000-0000-0000-0000-00000000001a'
\set offerExpiredCheckoutID '3a350000-0000-0000-0000-000000000024'
\set offerExpiredPendingID '3a350000-0000-0000-0000-000000000025'
\set userOfferGuardedID '3a350000-0000-0000-0000-00000000001b'
\set userQueueGuardedID '3a350000-0000-0000-0000-00000000001c'
\set userRequestGuardedID '3a350000-0000-0000-0000-00000000001f'
\set userCompletedID '3a350000-0000-0000-0000-000000000011'
\set userExpiredCheckoutID '3a350000-0000-0000-0000-000000000026'
\set userExpiredPendingID '3a350000-0000-0000-0000-000000000027'
\set userRefundPendingID '3a350000-0000-0000-0000-000000000012'
\set userRefundRecoveryID '3a350000-0000-0000-0000-000000000013'
\set window1CurrentID '3a350000-0000-0000-0000-000000000014'
\set window1OldID '3a350000-0000-0000-0000-000000000015'
\set window3ID '3a350000-0000-0000-0000-000000000016'
\set windowProtectedID '3a350000-0000-0000-0000-000000000017'

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
    'ticket-type-community',
    'Ticket Type Community',
    'A test community for ticket types',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Users with allocated protected ticket inventory
insert into "user" (user_id, auth_hash, email, username, email_verified)
values
    (
        :'userCompletedID',
        'test_hash',
        'completed-ticket-user@example.test',
        'completed-ticket-user',
        true
    ),
    (
        :'userRefundPendingID',
        'test_hash',
        'refund-pending-ticket-user@example.test',
        'refund-pending-ticket-user',
        true
    ),
    (
        :'userRefundRecoveryID',
        'test_hash',
        'refund-recovery-ticket-user@example.test',
        'refund-recovery-ticket-user',
        true
    ),
    (
        :'userOfferGuardedID',
        'test_hash',
        'guarded-offer-user@example.test',
        'guarded-offer-user',
        true
    ),
    (
        :'userQueueGuardedID',
        'test_hash',
        'guarded-queue-user@example.test',
        'guarded-queue-user',
        true
    ),
    (
        :'userRequestGuardedID',
        'test_hash',
        'guarded-request-user@example.test',
        'guarded-request-user',
        true
    );

-- Users with expired offer reservations ignored during seat reduction
insert into "user" (user_id, auth_hash, email, username, email_verified)
values
    (
        :'userExpiredCheckoutID',
        'test_hash',
        'expired-checkout-ticket-user@example.test',
        'expired-checkout-ticket-user',
        true
    ),
    (
        :'userExpiredPendingID',
        'test_hash',
        'expired-pending-ticket-user@example.test',
        'expired-pending-ticket-user',
        true
    );

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Ticket Group', 'ticket-group');

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values
    (
        :'eventID',
        :'groupID',
        'Ticket Types Event',
        'ticket-types-event',
        'Event used for ticket type sync tests',
        'UTC',
        :'eventCategoryID',
        'virtual'
    ),
    (
        :'eventGuardedID',
        :'groupID',
        'Guarded Ticket Types Event',
        'guarded-ticket-types-event',
        'Event used for active enrollment state guards',
        'UTC',
        :'eventCategoryID',
        'virtual'
    ),
    (
        :'eventProtectedID',
        :'groupID',
        'Protected Ticket Types Event',
        'protected-ticket-types-event',
        'Event used for protected ticket type checks',
        'UTC',
        :'eventCategoryID',
        'virtual'
    ),
    (
        :'eventWaitlistRemovalID',
        :'groupID',
        'Waitlist Removal Ticket Types Event',
        'waitlist-removal-ticket-types-event',
        'Event used for waitlist removal guards',
        'UTC',
        :'eventCategoryID',
        'virtual'
    );

-- Event whose only allocated ticket inventory is expired offers
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    'Event used for expired offer seat reduction',
    :'eventCategoryID',
    :'eventExpiredOffersID',
    'virtual',
    :'groupID',
    'Expired Offer Ticket Types Event',
    'expired-offer-ticket-types-event',
    'UTC'
);

-- Approval event used for pending ticket request guards
insert into event (
    attendee_approval_required,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    true,
    'Event used for pending ticket request guards',
    :'eventCategoryID',
    :'eventRequestedID',
    'virtual',
    :'groupID',
    'Requested Ticket Types Event',
    'requested-ticket-types-event',
    'UTC'
);

-- Event ticket types
insert into event_ticket_type (
    availability,
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values
    ('invitation_only', :'ticketType1ID', :'eventID', 1, 10, 'General admission'),
    ('public', :'ticketType2ID', :'eventID', 2, 5, 'VIP pass'),
    ('public', :'ticketTypeGuardedID', :'eventGuardedID', 1, 5, 'Guarded pass'),
    ('public', :'ticketTypeProtectedID', :'eventProtectedID', 1, 2, 'Protected pass'),
    ('public', :'ticketTypeRequestedID', :'eventRequestedID', 1, 5, 'Requested pass'),
    (
        'public',
        :'ticketTypeWaitlistRemovalID',
        :'eventWaitlistRemovalID',
        1,
        5,
        'Waitlist removal pass'
    );

-- Ticket type whose expired offers should not block a seat reduction
insert into event_ticket_type (
    availability,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    'public',
    :'eventExpiredOffersID',
    :'ticketTypeExpiredOffersID',
    1,
    2,
    'Expired offer pass'
);

-- Ticket type owned by another event for cross-parent validation
insert into event_ticket_type (
    event_ticket_type_id,
    description,
    event_id,
    "order",
    seats_total,
    title
) values
    (:'ticketType3ID', 'Workshop access', :'eventID', 3, 8, 'Workshop pass');

-- Event ticket price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'window1CurrentID', 2000, :'ticketType1ID'),
    (:'window1OldID', 2500, :'ticketType1ID'),
    (:'windowProtectedID', 3000, :'ticketTypeProtectedID');

-- Purchases allocating protected ticket inventory
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values
    (
        3000,
        'USD',
        :'eventProtectedID',
        :'ticketTypeProtectedID',
        'completed',
        'Protected pass',
        :'userCompletedID'
    ),
    (
        3000,
        'USD',
        :'eventProtectedID',
        :'ticketTypeProtectedID',
        'refund-pending',
        'Protected pass',
        :'userRefundPendingID'
    ),
    (
        3000,
        'USD',
        :'eventProtectedID',
        :'ticketTypeProtectedID',
        'refund-recovery-pending',
        'Protected pass',
        :'userRefundRecoveryID'
    );

-- Active offer that prevents deactivating its assigned tier
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'offerGuardedID',
    :'eventGuardedID',
    :'ticketTypeGuardedID',
    current_timestamp + interval '1 day',
    'organizer_invitation',
    'pending',
    :'userOfferGuardedID'
);

-- Expired ticket offers ignored by allocated-seat undershoot checks
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    created_at,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values
    (
        :'offerExpiredCheckoutID',
        0,
        current_timestamp - interval '2 hours',
        0,
        :'eventExpiredOffersID',
        :'ticketTypeExpiredOffersID',
        current_timestamp - interval '1 hour',
        'organizer_invitation',
        'checkout_pending',
        'Expired offer pass',
        :'userExpiredCheckoutID'
    ),
    (
        :'offerExpiredPendingID',
        null,
        current_timestamp - interval '3 hours',
        null,
        :'eventExpiredOffersID',
        :'ticketTypeExpiredOffersID',
        current_timestamp - interval '2 hours',
        'organizer_invitation',
        'pending',
        null,
        :'userExpiredPendingID'
    );

-- Queued user that keeps the selected tier active and public
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'eventGuardedID', :'ticketTypeGuardedID', :'userQueueGuardedID');

-- Queued user that prevents removing the selected tier
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'eventWaitlistRemovalID',
    :'ticketTypeWaitlistRemovalID',
    :'userQueueGuardedID'
);

-- Pending approval request that keeps its selected public tier available
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    status,
    user_id
) values (
    :'eventRequestedID',
    :'ticketTypeRequestedID',
    'pending',
    :'userRequestGuardedID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should upsert payload ticket types and remove omitted ticket types
select lives_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[
                {
                    "event_ticket_type_id": "%s",
                    "active": false,
                    "description": "Updated general admission",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2200,
                            "event_ticket_price_window_id": "%s"
                        }
                    ],
                    "seats_total": 12,
                    "title": "General admission updated"
                },
                {
                    "event_ticket_type_id": "%s",
                    "active": true,
                    "availability": "invitation_only",
                    "description": "Workshop access",
                    "order": 2,
                    "price_windows": [
                        {
                            "amount_minor": 1500,
                            "event_ticket_price_window_id": "%s"
                        }
                    ],
                    "seats_total": 8,
                    "title": "Workshop pass"
                }
            ]'::jsonb
        )$$,
        :'eventID',
        :'ticketType1ID',
        :'window1CurrentID',
        :'ticketType3ID',
        :'window3ID'
    ),
    'Should upsert payload ticket types and remove omitted ticket types'
);

-- Should update existing ticket types and remove omitted price windows
select is(
    (
        select jsonb_build_object(
            'active', active,
            'availability', availability,
            'description', description,
            'order', "order",
            'seats_total', seats_total,
            'title', title
        )
        from event_ticket_type
        where event_ticket_type_id = :'ticketType1ID'::uuid
    ),
    jsonb_build_object(
        'active', false,
        'availability', 'invitation_only',
        'description', 'Updated general admission',
        'order', 1,
        'seats_total', 12,
        'title', 'General admission updated'
    ),
    'Should update existing ticket types without replacing omitted availability'
);

-- Should insert new ticket types from the payload
select is(
    (
        select jsonb_build_object(
            'availability', availability,
            'description', description,
            'order', "order",
            'seats_total', seats_total,
            'title', title
        )
        from event_ticket_type
        where event_ticket_type_id = :'ticketType3ID'::uuid
    ),
    jsonb_build_object(
        'availability', 'invitation_only',
        'description', 'Workshop access',
        'order', 2,
        'seats_total', 8,
        'title', 'Workshop pass'
    ),
    'Should insert new ticket types from the payload'
);

-- Should remove ticket types omitted from the payload
select is(
    (select count(*) from event_ticket_type where event_ticket_type_id = :'ticketType2ID'::uuid),
    0::bigint,
    'Should remove ticket types omitted from the payload'
);

-- Should remove price windows omitted from the payload
select is(
    (select count(*) from event_ticket_price_window where event_ticket_price_window_id = :'window1OldID'::uuid),
    0::bigint,
    'Should remove price windows omitted from the payload'
);

-- Should reject updating a ticket type that belongs to another event
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[{"event_ticket_type_id": "%s", "order": 1, "price_windows": [{"amount_minor": 1000, "event_ticket_price_window_id": "%s"}], "seats_total": 1, "title": "Invalid"}]'::jsonb
        )$$,
        :'eventID',
        :'ticketTypeProtectedID',
        :'windowProtectedID'
    ),
    'ticket type does not belong to event',
    'Should reject updating a ticket type that belongs to another event'
);

-- Should reject updating a price window that belongs to another event
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[{"event_ticket_type_id": "%s", "order": 1, "price_windows": [{"amount_minor": 1000, "event_ticket_price_window_id": "%s"}], "seats_total": 1, "title": "Invalid"}]'::jsonb
        )$$,
        :'eventID',
        :'ticketType1ID',
        :'windowProtectedID'
    ),
    'ticket price window does not belong to event',
    'Should reject updating a price window that belongs to another event'
);

-- Should reject reassigning a price window to a different same-event ticket type
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[
                {"event_ticket_type_id": "%s", "order": 1, "price_windows": [{"amount_minor": 2200, "event_ticket_price_window_id": "%s"}], "seats_total": 12, "title": "General admission updated"},
                {"event_ticket_type_id": "%s", "order": 2, "price_windows": [{"amount_minor": 1000, "event_ticket_price_window_id": "%s"}], "seats_total": 1, "title": "Invalid"}
            ]'::jsonb
        )$$,
        :'eventID',
        :'ticketType1ID',
        :'window1CurrentID',
        :'ticketType3ID',
        :'window1CurrentID'
    ),
    'ticket price window does not belong to ticket type',
    'Should reject reassigning a price window to a different same-event ticket type'
);

-- Should reject removing ticket types with admission offers
select throws_ok(
    format(
        $$select sync_event_ticket_types('%s'::uuid, '[]'::jsonb)$$,
        :'eventGuardedID'
    ),
    'events require at least one ticket type',
    'Should reject removing ticket types with admission offers'
);

-- Should reject removing ticket types with invitation requests
select throws_ok(
    format(
        $$select sync_event_ticket_types('%s'::uuid, '[]'::jsonb)$$,
        :'eventRequestedID'
    ),
    'events require at least one ticket type',
    'Should reject removing ticket types with invitation requests'
);

-- Should reject removing ticket types with purchases
select throws_ok(
    format(
        $$select sync_event_ticket_types('%s'::uuid, '[]'::jsonb)$$,
        :'eventProtectedID'
    ),
    'events require at least one ticket type',
    'Should reject removing ticket types with purchases'
);

-- Should reject removing ticket types with waitlist entries
select throws_ok(
    format(
        $$select sync_event_ticket_types('%s'::uuid, '[]'::jsonb)$$,
        :'eventWaitlistRemovalID'
    ),
    'events require at least one ticket type',
    'Should reject removing ticket types with waitlist entries'
);

-- Should reduce seats below expired offer reservations
select lives_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[{"active": true, "availability": "public", "event_ticket_type_id": "%s", "order": 1, "price_windows": [], "seats_total": 0, "title": "Expired offer pass"}]'::jsonb
        )$$,
        :'eventExpiredOffersID',
        :'ticketTypeExpiredOffersID'
    ),
    'Should reduce seats below expired offer reservations'
);

select is(
    (
        select seats_total
        from event_ticket_type
        where event_ticket_type_id = :'ticketTypeExpiredOffersID'::uuid
    ),
    0,
    'Should persist the seat reduction below expired offer reservations'
);

-- Should reject seat totals below active offer reservations
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[{"active": true, "availability": "public", "event_ticket_type_id": "%s", "order": 1, "price_windows": [], "seats_total": 0, "title": "Guarded pass"}]'::jsonb
        )$$,
        :'eventGuardedID',
        :'ticketTypeGuardedID'
    ),
    'ticket type seats_total (0) cannot be less than current allocated seats (1)',
    'Should reject seat totals below active offer reservations'
);

-- Should reject seat totals below current purchased inventory
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[{"event_ticket_type_id": "%s", "order": 1, "price_windows": [{"amount_minor": 3000, "event_ticket_price_window_id": "%s"}], "seats_total": 0, "title": "Protected pass"}]'::jsonb
        )$$,
        :'eventProtectedID',
        :'ticketTypeProtectedID',
        :'windowProtectedID'
    ),
    'ticket type seats_total (0) cannot be less than current allocated seats (3)',
    'Should reject seat totals below current purchased inventory'
);

-- Should reject deactivating a tier with an active offer
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[{"active": false, "availability": "public", "event_ticket_type_id": "%s", "order": 1, "price_windows": [], "seats_total": 5, "title": "Guarded pass"}]'::jsonb
        )$$,
        :'eventGuardedID',
        :'ticketTypeGuardedID'
    ),
    'ticket types with active offers cannot be deactivated',
    'Should reject deactivating a tier with an active offer'
);

-- Should reject hiding a tier with a queued user
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[{"active": true, "availability": "invitation_only", "event_ticket_type_id": "%s", "order": 1, "price_windows": [], "seats_total": 5, "title": "Guarded pass"}]'::jsonb
        )$$,
        :'eventGuardedID',
        :'ticketTypeGuardedID'
    ),
    'ticket types with queued or pending requests must remain active and public',
    'Should reject hiding a tier with a queued user'
);

-- Should reject hiding a tier with a pending request
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            '%s'::uuid,
            '[{"active": true, "availability": "invitation_only", "event_ticket_type_id": "%s", "order": 1, "price_windows": [], "seats_total": 5, "title": "Requested pass"}]'::jsonb
        )$$,
        :'eventRequestedID',
        :'ticketTypeRequestedID'
    ),
    'ticket types with queued or pending requests must remain active and public',
    'Should reject hiding a tier with a pending request'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
