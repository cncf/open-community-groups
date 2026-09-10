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
\set ticketTypeGuardedRetainedID '3a350000-0000-0000-0000-000000000028'
\set ticketTypeProtectedID '3a350000-0000-0000-0000-000000000010'
\set ticketTypeProtectedRetainedID '3a350000-0000-0000-0000-000000000029'
\set ticketTypeRequestedID '3a350000-0000-0000-0000-00000000001e'
\set ticketTypeRequestedRetainedID '3a350000-0000-0000-0000-00000000002a'
\set ticketTypeWaitlistRemovalID '3a350000-0000-0000-0000-000000000021'
\set ticketTypeWaitlistRetainedID '3a350000-0000-0000-0000-00000000002b'
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

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userCompletedID');
select fx_user(:'userRefundPendingID');
select fx_user(:'userRefundRecoveryID');
select fx_user(:'userOfferGuardedID');
select fx_user(:'userQueueGuardedID');
select fx_user(:'userRequestGuardedID');
select fx_user(:'userExpiredCheckoutID');
select fx_user(:'userExpiredPendingID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventGuardedID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventProtectedID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventWaitlistRemovalID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

-- Event whose only allocated ticket inventory is expired offers
select fx_event(:'eventExpiredOffersID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

-- Approval event used for pending ticket request guards
select fx_event(:'eventRequestedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'event_kind_id', 'virtual'
));

-- Event ticket types
select fx_event_ticket_type(:'ticketType1ID', :'eventID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'ticketType2ID', :'eventID', jsonb_build_object(
    'order', 2,
    'seats_total', 5
));
select fx_event_ticket_type(:'ticketTypeGuardedID', :'eventGuardedID', jsonb_build_object(
    'seats_total', 5,
    'title', 'Guarded pass'
));
select fx_event_ticket_type(:'ticketTypeGuardedRetainedID', :'eventGuardedID', jsonb_build_object(
    'order', 2,
    'seats_total', 5,
    'title', 'Retained pass'
));
select fx_event_ticket_type(:'ticketTypeProtectedID', :'eventProtectedID', jsonb_build_object(
    'seats_total', 2,
    'title', 'Protected pass'
));
select fx_event_ticket_type(:'ticketTypeProtectedRetainedID', :'eventProtectedID', jsonb_build_object(
    'order', 2,
    'seats_total', 5,
    'title', 'Retained pass'
));
select fx_event_ticket_type(:'ticketTypeRequestedID', :'eventRequestedID', jsonb_build_object(
    'seats_total', 5,
    'title', 'Requested pass'
));
select fx_event_ticket_type(:'ticketTypeRequestedRetainedID', :'eventRequestedID', jsonb_build_object(
    'order', 2,
    'seats_total', 5,
    'title', 'Retained pass'
));
select fx_event_ticket_type(:'ticketTypeWaitlistRemovalID', :'eventWaitlistRemovalID', jsonb_build_object(
    'seats_total', 5
));
select fx_event_ticket_type(:'ticketTypeWaitlistRetainedID', :'eventWaitlistRemovalID', jsonb_build_object(
    'order', 2,
    'seats_total', 5,
    'title', 'Retained pass'
));

-- Ticket type whose expired offers should not block a seat reduction
select fx_event_ticket_type(:'ticketTypeExpiredOffersID', :'eventExpiredOffersID', jsonb_build_object(
    'seats_total', 2,
    'title', 'Expired offer pass'
));

-- Ticket type owned by another event for cross-parent validation
select fx_event_ticket_type(:'ticketType3ID', :'eventID', jsonb_build_object(
    'description', 'Workshop access',
    'order', 3,
    'seats_total', 8,
    'title', 'Workshop pass'
));

-- Event ticket price windows
select fx_event_ticket_price_window(:'window1CurrentID', :'ticketType1ID', jsonb_build_object('amount_minor', 2000));
select fx_event_ticket_price_window(:'window1OldID', :'ticketType1ID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'windowProtectedID', :'ticketTypeProtectedID', jsonb_build_object('amount_minor', 3000));

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
        0,
        'USD',
        :'eventProtectedID',
        :'ticketTypeProtectedID',
        'completed',
        'Protected pass',
        :'userCompletedID'
    ),
    (
        0,
        'USD',
        :'eventProtectedID',
        :'ticketTypeProtectedID',
        'refund-pending',
        'Protected pass',
        :'userRefundPendingID'
    ),
    (
        0,
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
    'ticket price window does not belong to ticket type',
    'Should reject reassigning a price window to a different same-event ticket type'
);

-- Should reject removing ticket types with admission offers
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            %L::uuid,
            '[{"active": true, "availability": "public", "event_ticket_type_id": "%s", "order": 1, "price_windows": [], "seats_total": 5, "title": "Retained pass"}]'::jsonb
        )$$,
        :'eventGuardedID',
        :'ticketTypeGuardedRetainedID'
    ),
    'OCG01',
    'ticket types with admission offers cannot be removed; deactivate them instead',
    'Should reject removing ticket types with admission offers'
);

-- Should reject removing ticket types with invitation requests
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            %L::uuid,
            '[{"active": true, "availability": "public", "event_ticket_type_id": "%s", "order": 1, "price_windows": [], "seats_total": 5, "title": "Retained pass"}]'::jsonb
        )$$,
        :'eventRequestedID',
        :'ticketTypeRequestedRetainedID'
    ),
    'OCG01',
    'ticket types with invitation requests cannot be removed; deactivate them instead',
    'Should reject removing ticket types with invitation requests'
);

-- Should reject removing ticket types with purchases
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            %L::uuid,
            '[{"active": true, "availability": "public", "event_ticket_type_id": "%s", "order": 1, "price_windows": [], "seats_total": 5, "title": "Retained pass"}]'::jsonb
        )$$,
        :'eventProtectedID',
        :'ticketTypeProtectedRetainedID'
    ),
    'OCG01',
    'ticket types with purchases cannot be removed; deactivate them instead',
    'Should reject removing ticket types with purchases'
);

-- Should reject removing ticket types with waitlist entries
select throws_ok(
    format(
        $$select sync_event_ticket_types(
            %L::uuid,
            '[{"active": true, "availability": "public", "event_ticket_type_id": "%s", "order": 1, "price_windows": [], "seats_total": 5, "title": "Retained pass"}]'::jsonb
        )$$,
        :'eventWaitlistRemovalID',
        :'ticketTypeWaitlistRetainedID'
    ),
    'OCG01',
    'ticket types with waitlist entries cannot be removed; deactivate them instead',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
    'ticket types with queued or pending requests must remain active and public',
    'Should reject hiding a tier with a pending request'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
