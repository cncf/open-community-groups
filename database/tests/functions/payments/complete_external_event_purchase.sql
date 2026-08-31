-- Tests completing pending external event purchases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'e07a0000-0000-0000-0000-000000000001'
\set attendeeID 'e07a0000-0000-0000-0000-000000000002'
\set communityID 'e07a0000-0000-0000-0000-000000000003'
\set completedAttendeeID 'e07a0000-0000-0000-0000-000000000010'
\set completedPurchaseID 'e07a0000-0000-0000-0000-000000000004'
\set eventCategoryID 'e07a0000-0000-0000-0000-000000000005'
\set eventID 'e07a0000-0000-0000-0000-000000000006'
\set eventTicketTypeID 'e07a0000-0000-0000-0000-000000000007'
\set expiredAttendeeID 'e07a0000-0000-0000-0000-000000000011'
\set expiredPurchaseID 'e07a0000-0000-0000-0000-000000000008'
\set groupCategoryID 'e07a0000-0000-0000-0000-000000000009'
\set groupID 'e07a0000-0000-0000-0000-00000000000a'
\set otherGroupID 'e07a0000-0000-0000-0000-00000000000b'
\set pendingPurchaseID 'e07a0000-0000-0000-0000-00000000000d'
\set priceWindowID 'e07a0000-0000-0000-0000-00000000000e'
\set stripeAttendeeID 'e07a0000-0000-0000-0000-000000000012'
\set stripePurchaseID 'e07a0000-0000-0000-0000-00000000000f'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for external completion scenarios
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
    'external-complete-community',
    'External Complete Community',
    'Community for external completion tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category for external completion scenarios
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category for external completion scenarios
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the purchases under test
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    :'groupCategoryID',
    :'groupID',
    'External Complete Group',
    'external-complete-group'
);

-- Separate group used by the ownership-rejection scenario
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    :'groupCategoryID',
    :'otherGroupID',
    'Other External Group',
    'other-external-group'
);

-- Organizer who marks the payment and attendee who holds the purchase
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'actorID', 'hash-actor', 'actor@example.test', true, 'external-actor'),
    (:'attendeeID', 'hash-attendee', 'attendee@example.test', true, 'external-attendee'),
    (
        :'completedAttendeeID',
        'hash-completed',
        'completed@example.test',
        true,
        'external-completed'
    ),
    (
        :'expiredAttendeeID',
        'hash-expired',
        'expired@example.test',
        true,
        'external-expired'
    ),
    (
        :'stripeAttendeeID',
        'hash-stripe',
        'stripe@example.test',
        true,
        'external-stripe'
    );

-- Published in-person event that can still be completed
insert into event (
    canceled,
    deleted,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    external_payment_url,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone,
    venue_address,
    venue_city,
    venue_country_code,
    venue_name,
    venue_zip_code
) values (
    false,
    false,
    'External completion event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    'https://pay.example.test/complete',
    :'groupID',
    'External Completion Event',
    true,
    'external-completion-event',
    current_timestamp + interval '7 days',
    'UTC',
    '1 Test Street',
    'Seoul',
    'KR',
    'Test Hall',
    '00000'
);

-- Paid ticket type for the completion event
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    :'eventID',
    :'eventTicketTypeID',
    1,
    50,
    'General admission'
);

-- Positive price window for the completion event
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values (
    5000,
    :'priceWindowID',
    :'eventTicketTypeID'
);

-- Pending external purchase completed by the happy-path scenario
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    'KRW',
    :'eventID',
    :'pendingPurchaseID',
    :'eventTicketTypeID',
    current_timestamp + interval '2 days',
    0,
    0,
    'pending',
    'General admission',
    :'attendeeID'
);

-- Already completed external purchase used by the idempotent scenario
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    external_payment_details,
    external_payment_marked_by_user_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    current_timestamp - interval '1 hour',
    'KRW',
    :'eventID',
    :'completedPurchaseID',
    :'eventTicketTypeID',
    'first mark',
    :'actorID',
    0,
    0,
    'completed',
    'General admission',
    :'completedAttendeeID'
);

-- Confirmed attendee row for the already completed purchase
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'confirmed', :'completedAttendeeID');

-- Expired external purchase rejected by the expiry scenario
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    'KRW',
    :'eventID',
    :'expiredPurchaseID',
    :'eventTicketTypeID',
    current_timestamp - interval '1 minute',
    0,
    0,
    'pending',
    'General admission',
    :'expiredAttendeeID'
);

-- Stripe purchase rejected by the charge-model boundary
insert into event_purchase (
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    5000,
    'direct-charge',
    'acct_external_complete',
    'KRW',
    :'eventID',
    :'stripePurchaseID',
    :'eventTicketTypeID',
    current_timestamp + interval '2 days',
    'stripe',
    'acct_external_complete',
    '{"connected_account_id":"acct_external_complete","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'none',
    'professional-event-admission',
    'General admission',
    :'stripeAttendeeID',
    '{"address":"1 Test Street","city":"Seoul","country_code":"KR","name":"Test Hall","zip_code":"00000"}'::jsonb
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should complete a pending external purchase and record the organizer marker
select is(
    complete_external_event_purchase(
        :'actorID'::uuid,
        :'groupID'::uuid,
        :'pendingPurchaseID'::uuid,
        'bank transfer ref 123',
        '[]'::jsonb,
        jsonb_build_object('event_name', 'External Complete Event')
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'transitioned', true,
        'user_id', :'attendeeID'::uuid
    ),
    'Should complete a pending external purchase and record the organizer marker'
);

select results_eq(
    format(
        $$
            select
                status,
                external_payment_details,
                external_payment_marked_by_user_id is not null,
                hold_expires_at is null
            from event_purchase
            where event_purchase_id = %L::uuid
        $$,
        :'pendingPurchaseID'
    ),
    $$
        values (
            'completed'::text,
            'bank transfer ref 123'::text,
            true,
            true
        )
    $$,
    'Should complete a pending external purchase and record the organizer marker'
);

-- Should write an audit log entry after marking an external purchase paid
select is(
    (
        select count(*)::int
        from audit_log
        where action = 'event_purchase_external_payment_completed'
        and resource_id = :'pendingPurchaseID'::uuid
    ),
    1,
    'Should write an audit log entry after marking an external purchase paid'
);

-- Should confirm attendance when marking an external purchase paid
select results_eq(
    format(
        $$
            select status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'attendeeID'
    ),
    $$ values ('confirmed'::text) $$,
    'Should confirm attendance when marking an external purchase paid'
);

-- Should enqueue the welcome notification with the completed purchase
select ok(
    exists(
        select 1
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-welcome'
        and n.user_id = :'attendeeID'::uuid
        and ntd.data->>'event_name' = 'External Complete Event'
    ),
    'Should enqueue the welcome notification with the completed purchase'
);

-- Should no-op on a repeated mark-paid for the same completed purchase
select is(
    complete_external_event_purchase(
        :'actorID'::uuid,
        :'groupID'::uuid,
        :'completedPurchaseID'::uuid,
        'second mark'
    )::jsonb ->> 'transitioned',
    'false',
    'Should no-op on a repeated mark-paid for the same completed purchase'
);

select is(
    (
        select external_payment_details
        from event_purchase
        where event_purchase_id = :'completedPurchaseID'::uuid
    ),
    'first mark',
    'Should no-op on a repeated mark-paid for the same completed purchase'
);

-- Should reject an expired external purchase
select throws_ok(
    format(
        $$select complete_external_event_purchase(%L::uuid, %L::uuid, %L::uuid, null)$$,
        :'actorID',
        :'groupID',
        :'expiredPurchaseID'
    ),
    'P0001',
    'purchase hold has expired',
    'Should reject an expired external purchase'
);

-- Should reject a purchase that belongs to another group
select throws_ok(
    format(
        $$select complete_external_event_purchase(%L::uuid, %L::uuid, %L::uuid, null)$$,
        :'actorID',
        :'otherGroupID',
        :'pendingPurchaseID'
    ),
    'P0001',
    'purchase not found',
    'Should reject a purchase that belongs to another group'
);

-- Should reject a Stripe purchase that cannot be marked paid locally
select throws_ok(
    format(
        $$select complete_external_event_purchase(%L::uuid, %L::uuid, %L::uuid, null)$$,
        :'actorID',
        :'groupID',
        :'stripePurchaseID'
    ),
    'P0001',
    'only external purchases can be marked paid locally',
    'Should reject a Stripe purchase that cannot be marked paid locally'
);

-- Should reject a missing purchase
select throws_ok(
    format(
        $$select complete_external_event_purchase(%L::uuid, %L::uuid, %L::uuid, null)$$,
        :'actorID',
        :'groupID',
        '00000000-0000-0000-0000-000000000000'
    ),
    'P0001',
    'purchase not found',
    'Should reject a missing purchase'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
