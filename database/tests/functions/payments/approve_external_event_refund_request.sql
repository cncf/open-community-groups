-- Tests locally approving external event refund requests.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'e07b0000-0000-0000-0000-000000000001'
\set attendeeID 'e07b0000-0000-0000-0000-000000000002'
\set communityID 'e07b0000-0000-0000-0000-000000000003'
\set eventCategoryID 'e07b0000-0000-0000-0000-000000000004'
\set eventID 'e07b0000-0000-0000-0000-000000000005'
\set eventTicketTypeID 'e07b0000-0000-0000-0000-000000000006'
\set groupCategoryID 'e07b0000-0000-0000-0000-000000000007'
\set groupID 'e07b0000-0000-0000-0000-000000000008'
\set pendingRequestPurchaseID 'e07b0000-0000-0000-0000-000000000009'
\set priceWindowID 'e07b0000-0000-0000-0000-00000000000a'
\set refundedAttendeeID 'e07b0000-0000-0000-0000-00000000000b'
\set refundedPurchaseID 'e07b0000-0000-0000-0000-00000000000c'
\set refundRequestID 'e07b0000-0000-0000-0000-00000000000d'
\set refundedRequestID 'e07b0000-0000-0000-0000-00000000000e'
\set leftoverAttendeeID 'e07b0000-0000-0000-0000-000000000011'
\set leftoverPurchaseID 'e07b0000-0000-0000-0000-000000000012'
\set leftoverRequestID 'e07b0000-0000-0000-0000-000000000013'
\set replacementOldPurchaseID 'e07b0000-0000-0000-0000-000000000015'
\set replacementRequestID 'e07b0000-0000-0000-0000-000000000017'
\set replacementUserID 'e07b0000-0000-0000-0000-000000000014'
\set stripeAttendeeID 'e07b0000-0000-0000-0000-00000000000f'
\set stripePurchaseID 'e07b0000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for external refund-approval scenarios
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
    'external-refund-community',
    'External Refund Community',
    'Community for external refund tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category for external refund-approval scenarios
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category for external refund-approval scenarios
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
    'External Refund Group',
    'external-refund-group'
);

-- Organizer and attendees used by refund-approval scenarios
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'actorID', 'hash-actor', 'refund-actor@example.test', true, 'refund-actor'),
    (:'attendeeID', 'hash-attendee', 'refund-attendee@example.test', true, 'refund-attendee'),
    (
        :'leftoverAttendeeID',
        'hash-leftover',
        'leftover@example.test',
        true,
        'leftover-attendee'
    ),
    (
        :'refundedAttendeeID',
        'hash-refunded',
        'refunded@example.test',
        true,
        'refunded-attendee'
    ),
    (
        :'replacementUserID',
        'hash-replacement',
        'refund-replacement@example.test',
        true,
        'refund-replacement'
    ),
    (
        :'stripeAttendeeID',
        'hash-stripe',
        'refund-stripe@example.test',
        true,
        'refund-stripe'
    );

-- Published event used by refund-approval scenarios
insert into event (
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
    timezone
) values (
    'External refund event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    'https://pay.example.test/refund',
    :'groupID',
    'External Refund Event',
    true,
    'external-refund-event',
    current_timestamp + interval '7 days',
    'UTC'
);

-- Paid ticket type for the refund event
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

-- Positive price window for the refund event
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values (
    5000,
    :'priceWindowID',
    :'eventTicketTypeID'
);

-- External purchase waiting for organizer refund approval
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    current_timestamp - interval '1 day',
    'KRW',
    :'eventID',
    :'pendingRequestPurchaseID',
    :'eventTicketTypeID',
    0,
    0,
    'refund-requested',
    'General admission',
    :'attendeeID'
);

-- Pending refund request approved by the happy-path scenario
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status
) values (
    :'pendingRequestPurchaseID',
    :'refundRequestID',
    :'attendeeID',
    'pending'
);

-- Confirmed attendee canceled by the happy-path approval
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'confirmed', :'attendeeID');

-- Already refunded external purchase used by the idempotent scenario
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    refunded_at,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    current_timestamp - interval '2 days',
    'KRW',
    :'eventID',
    :'refundedPurchaseID',
    :'eventTicketTypeID',
    0,
    0,
    current_timestamp - interval '1 hour',
    'refunded',
    'General admission',
    :'refundedAttendeeID'
);

-- Approved refund request for the already refunded purchase
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    reviewed_at,
    reviewed_by_user_id,
    status
) values (
    :'refundedPurchaseID',
    :'refundedRequestID',
    :'refundedAttendeeID',
    current_timestamp - interval '1 hour',
    :'actorID',
    'approved'
);

-- Already refunded external purchase with a leftover pending request
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    refunded_at,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    current_timestamp - interval '2 days',
    'KRW',
    :'eventID',
    :'leftoverPurchaseID',
    :'eventTicketTypeID',
    0,
    0,
    current_timestamp - interval '1 hour',
    'refunded',
    'General admission',
    :'leftoverAttendeeID'
);

-- Pending refund request stranded after a local external refund
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status
) values (
    :'leftoverPurchaseID',
    :'leftoverRequestID',
    :'leftoverAttendeeID',
    'pending'
);

-- Refund-requested purchase whose attendee is still answering registration questions
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    current_timestamp - interval '1 day',
    'KRW',
    :'eventID',
    :'replacementOldPurchaseID',
    :'eventTicketTypeID',
    0,
    0,
    'refund-requested',
    'General admission',
    :'replacementUserID'
);

-- Pending refund request on the questionnaire-pending purchase
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status
) values (
    :'replacementOldPurchaseID',
    :'replacementRequestID',
    :'replacementUserID',
    'pending'
);

-- Questionnaire-pending attendee canceled when no replacement purchase exists
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'registration-questions-pending', :'replacementUserID');

-- Stripe purchase rejected by the charge-model boundary
insert into event_purchase (
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    seller_snapshot,
    status,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    5000,
    'direct-charge',
    'acct_external_refund',
    'KRW',
    :'eventID',
    :'stripePurchaseID',
    :'eventTicketTypeID',
    0,
    'stripe',
    'ch_external_refund',
    'cs_external_refund',
    'acct_external_refund',
    'pi_external_refund',
    5000,
    '{"connected_account_id":"acct_external_refund","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'refund-requested',
    5000,
    0,
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

-- Should approve an external refund request and refund the purchase locally
select is(
    approve_external_event_refund_request(
        :'actorID'::uuid,
        :'groupID'::uuid,
        :'pendingRequestPurchaseID'::uuid,
        'returned by bank transfer',
        jsonb_build_object('event_name', 'External Refund Event')
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'transitioned', true,
        'user_id', :'attendeeID'::uuid
    ),
    'Should approve an external refund request and refund the purchase locally'
);

select results_eq(
    format(
        $$
            select ep.status, err.status
            from event_purchase ep
            join event_refund_request err using (event_purchase_id)
            where ep.event_purchase_id = %L::uuid
        $$,
        :'pendingRequestPurchaseID'
    ),
    $$ values ('refunded'::text, 'approved'::text) $$,
    'Should approve an external refund request and refund the purchase locally'
);

-- Should cancel confirmed attendance when an external refund is approved
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
    $$ values ('attendance-canceled'::text) $$,
    'Should cancel confirmed attendance when an external refund is approved'
);

-- Should enqueue the refund-approved notification with the approval
select ok(
    exists(
        select 1
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-refund-approved'
        and n.user_id = :'attendeeID'::uuid
        and ntd.data->>'event_name' = 'External Refund Event'
    ),
    'Should enqueue the refund-approved notification with the approval'
);

-- Should no-op on a repeated approval for an already refunded purchase
select is(
    approve_external_event_refund_request(
        :'actorID'::uuid,
        :'groupID'::uuid,
        :'refundedPurchaseID'::uuid,
        null
    )::jsonb ->> 'transitioned',
    'false',
    'Should no-op on a repeated approval for an already refunded purchase'
);

-- Should approve a leftover pending request on an already refunded purchase
select is(
    approve_external_event_refund_request(
        :'actorID'::uuid,
        :'groupID'::uuid,
        :'leftoverPurchaseID'::uuid,
        null
    )::jsonb ->> 'transitioned',
    'false',
    'Should approve a leftover pending request on an already refunded purchase'
);

select is(
    (
        select err.status
        from event_refund_request err
        where err.event_refund_request_id = :'leftoverRequestID'::uuid
    ),
    'approved'::text,
    'Should approve a leftover pending request on an already refunded purchase'
);
select throws_ok(
    format(
        $$select approve_external_event_refund_request(%L::uuid, %L::uuid, %L::uuid, null)$$,
        :'actorID',
        :'groupID',
        :'stripePurchaseID'
    ),
    'P0001',
    'only external purchases can be refunded locally',
    'Should reject a Stripe purchase that cannot be refunded locally'
);

-- Should reject a missing refund request
select throws_ok(
    format(
        $$select approve_external_event_refund_request(%L::uuid, %L::uuid, %L::uuid, null)$$,
        :'actorID',
        :'groupID',
        '00000000-0000-0000-0000-000000000000'
    ),
    'P0001',
    'refund request not found',
    'Should reject a missing refund request'
);

-- Should cancel a questionnaire-pending attendee when an external refund is approved
select is(
    approve_external_event_refund_request(
        :'actorID'::uuid,
        :'groupID'::uuid,
        :'replacementOldPurchaseID'::uuid,
        'returned after replacement'
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'transitioned', true,
        'user_id', :'replacementUserID'::uuid
    ),
    'Should cancel a questionnaire-pending attendee when an external refund is approved'
);

select results_eq(
    format(
        $$
            select ea.status, ep.status
            from event_attendee ea
            join event_purchase ep
                on ep.event_id = ea.event_id
                and ep.user_id = ea.user_id
                and ep.event_purchase_id = %L::uuid
            where ea.event_id = %L::uuid
            and ea.user_id = %L::uuid
        $$,
        :'replacementOldPurchaseID',
        :'eventID',
        :'replacementUserID'
    ),
    $$ values ('attendance-canceled'::text, 'refunded'::text) $$,
    'Should cancel a questionnaire-pending attendee when an external refund is approved'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
