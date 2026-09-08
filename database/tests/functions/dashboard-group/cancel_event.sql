-- Tests canceling events and closing enrollment.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(24);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a060000-0000-0000-0000-000000000001'
\set eventCategoryID '3a060000-0000-0000-0000-000000000002'
\set eventAlreadyCanceledID '3a060000-0000-0000-0000-000000000023'
\set eventExternalID '3a060000-0000-0000-0000-00000000002b'
\set eventID '3a060000-0000-0000-0000-000000000003'
\set eventInvalidPaymentID '3a060000-0000-0000-0000-000000000019'
\set eventNoMeetingID '3a060000-0000-0000-0000-000000000004'
\set eventPastID '3a060000-0000-0000-0000-000000000024'
\set externalCompletedPurchaseID '3a060000-0000-0000-0000-00000000002c'
\set externalCompletedUserID '3a060000-0000-0000-0000-00000000002d'
\set externalPendingPurchaseID '3a060000-0000-0000-0000-00000000002e'
\set externalPendingUserID '3a060000-0000-0000-0000-00000000002f'
\set externalTicketTypeID '3a060000-0000-0000-0000-000000000030'
\set freePurchaseID '3a060000-0000-0000-0000-000000000011'
\set freeRefundRequestID '3a060000-0000-0000-0000-000000000012'
\set freeUserID '3a060000-0000-0000-0000-000000000013'
\set groupCategoryID '3a060000-0000-0000-0000-000000000005'
\set groupID '3a060000-0000-0000-0000-000000000006'
\set siteID '3a060000-0000-0000-0000-000000000031'
\set invalidPaymentPurchaseID '3a060000-0000-0000-0000-000000000022'
\set invalidPaymentTicketTypeID '3a060000-0000-0000-0000-000000000021'
\set invalidPaymentUserID '3a060000-0000-0000-0000-000000000020'
\set invitationUserID '3a060000-0000-0000-0000-000000000017'
\set missingGroupID '3a060000-0000-0000-0000-000000000007'
\set paidPurchaseID '3a060000-0000-0000-0000-000000000014'
\set paidRefundRequestID '3a060000-0000-0000-0000-000000000018'
\set paidUserID '3a060000-0000-0000-0000-000000000015'
\set rejectedPaidPurchaseID '3a060000-0000-0000-0000-000000000025'
\set rejectedPaidRefundRequestID '3a060000-0000-0000-0000-000000000026'
\set rejectedPaidUserID '3a060000-0000-0000-0000-000000000027'
\set sessionMeetingID '3a060000-0000-0000-0000-000000000008'
\set sessionNoMeetingID '3a060000-0000-0000-0000-000000000009'
\set offerID '3a060000-0000-0000-0000-000000000028'
\set offerUserID '3a060000-0000-0000-0000-000000000029'
\set userID '3a060000-0000-0000-0000-000000000010'
\set ticketTypeID '3a060000-0000-0000-0000-000000000016'
\set waitlistUserID '3a060000-0000-0000-0000-00000000002a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Site theme used by external payment expiry notifications
insert into site (description, site_id, theme, title)
values (
    'Cancel event site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Cancel Event Site'
);

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'communityID',
    'Test Group',
    'test-group',
    'A test group',
    :'groupCategoryID'
);

-- User (as previously published_by)
insert into "user" (
    user_id,
    auth_hash,
    email,
    username
) values (
    :'userID',
    'x',
    'user@test.local',
    'user'
);

-- Attendees covering free, paid, invalid-payment, and invitation scenarios
insert into "user" (user_id, auth_hash, email, username) values
    (:'externalCompletedUserID', 'external-completed', 'external-completed@test.local', 'external-completed'),
    (:'externalPendingUserID', 'external-pending', 'external-pending@test.local', 'external-pending'),
    (:'freeUserID', 'free', 'free@test.local', 'free-user'),
    (:'invalidPaymentUserID', 'invalid', 'invalid@test.local', 'invalid-user'),
    (:'invitationUserID', 'invited', 'invited@test.local', 'invited-user'),
    (:'offerUserID', 'offer', 'offer@test.local', 'offer-user'),
    (:'paidUserID', 'paid', 'paid@test.local', 'paid-user'),
    (:'rejectedPaidUserID', 'rejected', 'rejected@test.local', 'rejected-user'),
    (
        :'waitlistUserID',
        'waitlist',
        'waitlist@test.local',
        'waitlist-user'
    );

-- Event (published, not canceled)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,

    canceled,
    capacity,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    published,
    published_at,
    published_by,
    waitlist_enabled
) values (
    :'eventID',
    :'groupID',
    'Test Event',
    'test-event',
    'A test event',
    'UTC',
    :'eventCategoryID',
    'virtual',
    now() + interval '1 day',
    now() + interval '1 day 1 hour',

    false,
    100,
    true,
    'zoom',
    true,
    true,
    now(),
    :'userID',
    true
);

-- Event without meeting_requested (to verify meeting_in_sync is not changed)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_requested,
    published,
    published_at,
    published_by,
    canceled
) values (
    :'eventNoMeetingID',
    :'groupID',
    'Test Event No Meeting',
    'test-event-no-meeting',
    'A test event without meeting',
    'UTC',
    :'eventCategoryID',
    'in-person',
    now(),
    now() + interval '1 hour',
    null,
    false,
    true,
    now(),
    :'userID',
    false
);

-- Events rejected because they are already canceled, completed, or not refund-ready
insert into event (
    canceled,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values
    (true, 'Canceled event', now() + interval '1 day 1 hour', :'eventCategoryID', :'eventAlreadyCanceledID', 'in-person', :'groupID', 'Already Canceled', true, 'already-canceled', now() + interval '1 day', 'UTC'),
    (false, 'Invalid payment event', now() + interval '1 day 1 hour', :'eventCategoryID', :'eventInvalidPaymentID', 'in-person', :'groupID', 'Invalid Payment', true, 'invalid-payment', now() + interval '1 day', 'UTC'),
    (false, 'Past event', now() - interval '1 hour', :'eventCategoryID', :'eventPastID', 'in-person', :'groupID', 'Past', true, 'past', now() - interval '2 hours', 'UTC');

-- Session with meeting_requested=true (should be marked as out of sync)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionMeetingID',
    :'eventID',
    'Session With Meeting',
    now() + interval '1 day',
    now() + interval '1 day 30 minutes',
    'virtual',
    true,
    'zoom',
    true
);

-- Session with meeting_requested=false (should NOT be marked as out of sync)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_requested
) values (
    :'sessionNoMeetingID',
    :'eventID',
    'Session Without Meeting',
    now() + interval '1 day 30 minutes',
    now() + interval '1 day 1 hour',
    'in-person',
    null,
    false
);

-- Ticket types used by refundable and invalid-payment purchases
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values
    (:'ticketTypeID', :'eventID', 1, 100, 'General admission'),
    (:'invalidPaymentTicketTypeID', :'eventInvalidPaymentID', 1, 100, 'Invalid payment');

-- Attendees covering confirmed attendance, pending invitations, and validation rollback
insert into event_attendee (checked_in, checked_in_at, event_id, status, user_id) values
    (true, current_timestamp, :'eventID', 'confirmed', :'freeUserID'),
    (false, null, :'eventID', 'invitation-pending', :'invitationUserID'),
    (true, current_timestamp, :'eventID', 'confirmed', :'paidUserID'),
    (true, current_timestamp, :'eventID', 'confirmed', :'rejectedPaidUserID'),
    (true, current_timestamp, :'eventInvalidPaymentID', 'confirmed', :'invalidPaymentUserID');

-- Purchases covering free, provider-backed, and invalid refund handoffs
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_payment_reference,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_total_minor,
    seller_snapshot,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
)
select
    fixture.amount_minor,
    fixture.currency_code,
    fixture.event_id,
    fixture.event_purchase_id,
    fixture.event_ticket_type_id,
    fixture.payment_provider_id,
    fixture.provider_payment_reference,
    fixture.status,
    fixture.ticket_title,
    fixture.user_id,

    case when fixture.amount_minor > 0 then 'direct-charge' else 'ocg-free' end,
    case when fixture.amount_minor > 0 then 'acct_cancel_test' end,
    case when fixture.amount_minor > 0 then 0 end,
    case when fixture.amount_minor > 0 then 'ch_' || fixture.event_purchase_id end,
    case when fixture.amount_minor > 0 then 'cs_' || fixture.event_purchase_id end,
    case when fixture.amount_minor > 0 then 'acct_cancel_test' end,
    case when fixture.amount_minor > 0 then fixture.amount_minor end,
    case when fixture.amount_minor > 0 then '{}'::jsonb end,
    case when fixture.amount_minor > 0 then fixture.amount_minor end,
    case when fixture.amount_minor > 0 then 0 end,
    case when fixture.amount_minor > 0 then 'inclusive' end,
    case when fixture.amount_minor > 0 then 'manual' end,
    case when fixture.amount_minor > 0 then 'professional-event-admission' end,
    case when fixture.amount_minor > 0 then '{}'::jsonb end
from (
    values
        (0, 'USD', :'eventID'::uuid, :'freePurchaseID'::uuid, :'ticketTypeID'::uuid, null::text, null::text, 'refund-requested', 'General admission', :'freeUserID'::uuid),
        (2500, 'USD', :'eventID'::uuid, :'paidPurchaseID'::uuid, :'ticketTypeID'::uuid, 'stripe', 'pi_cancel_paid', 'refund-requested', 'General admission', :'paidUserID'::uuid),
        (2500, 'USD', :'eventID'::uuid, :'rejectedPaidPurchaseID'::uuid, :'ticketTypeID'::uuid, 'stripe', 'pi_cancel_rejected', 'completed', 'General admission', :'rejectedPaidUserID'::uuid)
) as fixture(
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_payment_reference,
    status,
    ticket_title,
    user_id
);

-- Pending free and paid attendee refund requests completed or queued by cancellation
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status
) values
    (:'freePurchaseID', :'freeRefundRequestID', :'freeUserID', 'pending'),
    (:'paidPurchaseID', :'paidRefundRequestID', :'paidUserID', 'pending'),
    (:'rejectedPaidPurchaseID', :'rejectedPaidRefundRequestID', :'rejectedPaidUserID', 'rejected');

-- Active ticket offer canceled with the event
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    organizer_user_id,
    source,
    status,
    user_id
) values (
    :'offerID',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    :'userID',
    'organizer_invitation',
    'pending',
    :'offerUserID'
);

-- Ticket-tier FIFO queue cleared with the event
insert into event_waitlist (
    event_id,
    event_ticket_type_id,
    user_id
) values (
    :'eventID',
    :'ticketTypeID',
    :'waitlistUserID'
);

-- External-marked event canceled with pending and completed external purchases
insert into event (
    canceled,
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
    false,
    'External cancellation event',
    :'eventCategoryID',
    :'eventExternalID',
    'in-person',
    'https://pay.example.test/cancel',
    :'groupID',
    'External Cancel Event',
    true,
    'external-cancel-event',
    current_timestamp + interval '2 days',
    'UTC'
);

-- Ticket type for the external cancellation event
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'externalTicketTypeID',
    :'eventExternalID',
    1,
    50,
    'External admission'
);

-- Confirmed attendee for the completed external purchase
insert into event_attendee (event_id, status, user_id)
values (:'eventExternalID', 'confirmed', :'externalCompletedUserID');

-- Pending external hold expired with a do-not-pay notice on cancellation
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
    :'eventExternalID',
    :'externalPendingPurchaseID',
    :'externalTicketTypeID',
    current_timestamp + interval '2 days',
    0,
    0,
    'pending',
    'External admission',
    :'externalPendingUserID'
);

-- Completed external purchase refunded locally on cancellation
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
    current_timestamp - interval '1 hour',
    'KRW',
    :'eventExternalID',
    :'externalCompletedPurchaseID',
    :'externalTicketTypeID',
    0,
    0,
    'completed',
    'External admission',
    :'externalCompletedUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject an already canceled event
select throws_ok(
    format(
        $$select cancel_event(%L::uuid, %L::uuid, %L::uuid)$$,
        :'userID', :'groupID', :'eventAlreadyCanceledID'
    ),
    'event not found or inactive',
    'Should reject an already canceled event'
);

-- Should reject a completed past event
select throws_ok(
    format(
        $$select cancel_event(%L::uuid, %L::uuid, %L::uuid)$$,
        :'userID', :'groupID', :'eventPastID'
    ),
    'event not found or inactive',
    'Should reject a completed past event'
);

-- Should mark as canceled and preserve publication metadata
select lives_ok(
    format(
        $$select cancel_event(null::uuid, %L::uuid, %L::uuid)$$,
        :'groupID', :'eventID'
    ),
    'Should mark as canceled and preserve publication metadata'
);

-- Should set canceled=true
select is(
    (select canceled from event where event_id = :'eventID'),
    true,
    'Should set canceled=true'
);

-- Should keep published=true
select is(
    (select published from event where event_id = :'eventID'),
    true,
    'Should keep published=true'
);

-- Should keep published_at
select isnt(
    (select published_at from event where event_id = :'eventID'),
    null::timestamptz,
    'Should keep published_at'
);

-- Should finalize free purchases and queue provider-backed refunds
select results_eq(
    format($$
        select ep.event_purchase_id, ep.status, epr.kind, epr.status
        from event_purchase ep
        left join event_purchase_refund epr using (event_purchase_id)
        where ep.event_id = %L::uuid
        order by ep.event_purchase_id
    $$, :'eventID'),
    format($$ values
        (%L::uuid, 'refunded'::text, null::text, null::text),
        (%L::uuid, 'refund-pending'::text, 'event-cancellation'::text, 'provider-pending'::text),
        (%L::uuid, 'refund-pending'::text, 'event-cancellation'::text, 'provider-pending'::text)
    $$, :'freePurchaseID', :'paidPurchaseID', :'rejectedPaidPurchaseID'),
    'Should finalize free purchases and queue provider-backed refunds'
);

-- Should preserve attendance history and cancel pending invitations
select results_eq(
    format($$
        select checked_in, status
        from event_attendee
        where event_id = %L::uuid
        order by user_id
    $$, :'eventID'),
    $$ values
        (false, 'attendance-canceled'::text),
        (false, 'attendance-canceled'::text),
        (false, 'invitation-canceled'::text),
        (false, 'attendance-canceled'::text)
    $$,
    'Should preserve attendance history and cancel pending invitations'
);

-- Should complete free-purchase refund requests locally
select is(
    (select status from event_refund_request where event_refund_request_id = :'freeRefundRequestID'),
    'approved',
    'Should complete free-purchase refund requests locally'
);

-- Should move paid refund requests into worker approval state
select results_eq(
    format($$
        select err.status, epr.event_refund_request_id, epr.kind, epr.status
        from event_refund_request err
        join event_purchase_refund epr using (event_refund_request_id)
        where err.event_refund_request_id = %L::uuid
    $$, :'paidRefundRequestID'),
    format($$ values ('approving'::text, %L::uuid, 'event-cancellation'::text, 'provider-pending'::text) $$, :'paidRefundRequestID'),
    'Should move paid refund requests into worker approval state'
);

-- Should preserve rejected request history without attaching it to cancellation work
select results_eq(
    format($$
        select err.status, epr.event_refund_request_id
        from event_refund_request err
        join event_purchase_refund epr using (event_purchase_id)
        where err.event_refund_request_id = %L::uuid
    $$, :'rejectedPaidRefundRequestID'),
    $$ values ('rejected'::text, null::uuid) $$,
    'Should preserve rejected request history without attaching it to cancellation work'
);

-- Should keep published_by
select is(
    (select published_by from event where event_id = :'eventID'),
    :'userID'::uuid,
    'Should keep published_by'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            event_id,
            resource_type,
            resource_id
        from audit_log
        where action = 'event_canceled'
    $$,
    format(
        $$
        values (
            'event_canceled',
            null::uuid,
            null::text,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'event',
            %L::uuid
        )
        $$,
        :'communityID', :'groupID', :'eventID', :'eventID'
    ),
    'Should create the expected audit row'
);

-- Should cancel active offers and clear queues with the event
select results_eq(
    format(
        $$
            select
                (
                    select status
                    from admission_offer
                    where admission_offer_id = %L::uuid
                ),
                (
                    select count(*)
                    from event_waitlist
                    where event_id = %L::uuid
                )
        $$,
        :'offerID',
        :'eventID'
    ),
    $$ values ('canceled'::text, 0::bigint) $$,
    'Should cancel active offers and clear queues with the event'
);

-- Should mark meeting_in_sync false when meeting was requested
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    false,
    'Should mark meeting_in_sync false when meeting was requested'
);

-- Should set session meeting_in_sync to false when meeting_requested=true
select is(
    (select meeting_in_sync from session where session_id = :'sessionMeetingID'),
    false,
    'Should set session meeting_in_sync=false when meeting_requested=true'
);

-- Should not change session meeting_in_sync when meeting_requested=false
select is(
    (select meeting_in_sync from session where session_id = :'sessionNoMeetingID'),
    null,
    'Should not change session meeting_in_sync when meeting_requested=false'
);

-- Should not change event meeting_in_sync when meeting_requested=false
select lives_ok(
    format(
        $$select cancel_event(null::uuid, %L::uuid, %L::uuid)$$,
        :'groupID', :'eventNoMeetingID'
    ),
    'Should cancel event when meeting_requested=false'
);

-- Should keep event meeting_in_sync unchanged when meeting_requested=false
select is(
    (select meeting_in_sync from event where event_id = :'eventNoMeetingID'),
    null,
    'Should keep event meeting_in_sync unchanged when meeting_requested=false'
);

-- Should throw error when group_id does not match
select throws_ok(
    format(
        $$select cancel_event(null::uuid, %L::uuid, %L::uuid)$$,
        :'missingGroupID', :'eventID'
    ),
    'event not found or inactive',
    'Should throw error when group_id does not match'
);

-- Should cancel an external-marked event with pending and completed purchases
select lives_ok(
    format(
        $$select cancel_event(%L::uuid, %L::uuid, %L::uuid)$$,
        :'userID', :'groupID', :'eventExternalID'
    ),
    'Should cancel an external-marked event with pending and completed purchases'
);

-- Should expire pending external holds and refund completed purchases locally
select results_eq(
    format(
        $$
            select ep.event_purchase_id, ep.status, epr.event_purchase_refund_id
            from event_purchase ep
            left join event_purchase_refund epr using (event_purchase_id)
            where ep.event_id = %L::uuid
            order by ep.event_purchase_id
        $$,
        :'eventExternalID'
    ),
    format(
        $$
            values
                (%L::uuid, 'refunded'::text, null::uuid),
                (%L::uuid, 'expired'::text, null::uuid)
        $$,
        :'externalCompletedPurchaseID',
        :'externalPendingPurchaseID'
    ),
    'Should expire pending external holds and refund completed purchases locally'
);

-- Should enqueue a do-not-pay notice for expired external payment holds
select ok(
    exists(
        select 1
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-external-payment-expired'
        and n.user_id = :'externalPendingUserID'::uuid
        and (ntd.data->>'do_not_pay')::boolean = true
        and (ntd.data->>'event_purchase_id')::uuid = :'externalPendingPurchaseID'::uuid
    ),
    'Should enqueue a do-not-pay notice for expired external payment holds'
);

-- Should preserve attendance history for completed external purchases
select is(
    (
        select status
        from event_attendee
        where event_id = :'eventExternalID'::uuid
        and user_id = :'externalCompletedUserID'::uuid
    ),
    'attendance-canceled',
    'Should preserve attendance history for completed external purchases'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
