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

-- Baseline community, categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'externalCompletedUserID');
select fx_user(:'externalPendingUserID');
select fx_user(:'freeUserID');
select fx_user(:'invalidPaymentUserID');
select fx_user(:'invitationUserID');
select fx_user(:'offerUserID');
select fx_user(:'paidUserID');
select fx_user(:'rejectedPaidUserID');
select fx_user(:'waitlistUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');


-- Site theme used by external payment expiry notifications
insert into site (description, site_id, theme, title)
values (
    'Cancel event site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Cancel Event Site'
);

-- Event Category
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'General'));

-- User (as previously published_by)
select fx_user(:'userID', jsonb_build_object('username', 'user-cancel-event'));

-- Event (published, not canceled)
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'published_at', now(),
    'published_by', :'userID',
    'starts_at', now() + interval '1 day',
    'waitlist_enabled', true
));

-- Event without meeting_requested (to verify meeting_in_sync is not changed)
select fx_event(:'eventNoMeetingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 hour',
    'meeting_requested', false,
    'published', true,
    'published_at', now(),
    'published_by', :'userID',
    'starts_at', now()
));

-- Events rejected because they are already canceled, completed, or not refund-ready
select fx_event(:'eventAlreadyCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '1 day 1 hour',
    'published', true,
    'starts_at', now() + interval '1 day'
));
select fx_event(:'eventInvalidPaymentID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 day 1 hour',
    'published', true,
    'starts_at', now() + interval '1 day'
));
select fx_event(:'eventPastID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 hour',
    'name', 'Past',
    'published', true,
    'slug', 'past',
    'starts_at', now() - interval '2 hours'
));

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
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General admission'
));
select fx_event_ticket_type(:'invalidPaymentTicketTypeID', :'eventInvalidPaymentID', jsonb_build_object('seats_total', 100));

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
select fx_event(:'eventExternalID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/cancel',
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Ticket type for the external cancellation event
select fx_event_ticket_type(:'externalTicketTypeID', :'eventExternalID', jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));

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
    'OCG01',
    'event not found or inactive',
    'Should reject an already canceled event'
);

-- Should reject a completed past event
select throws_ok(
    format(
        $$select cancel_event(%L::uuid, %L::uuid, %L::uuid)$$,
        :'userID', :'groupID', :'eventPastID'
    ),
    'OCG01',
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
        select
            ep.event_purchase_id,
            ep.status,
            epr.kind,
            epr.status,
            pj.idempotency_key,
            pj.kind,
            pj.status
        from event_purchase ep
        left join event_purchase_refund epr using (event_purchase_id)
        left join payment_job pj on pj.payment_job_id = epr.payment_job_id
        where ep.event_id = %L::uuid
        order by ep.event_purchase_id
    $$, :'eventID'),
    format($$ values
        (%L::uuid, 'refunded'::text, null::text, null::text, null::text, null::text, null::text),
        (%L::uuid, 'refund-pending'::text, 'event-cancellation'::text, 'provider-pending'::text, 'event-purchase-refund-%s'::text, 'event-purchase-refund'::text, 'pending'::text),
        (%L::uuid, 'refund-pending'::text, 'event-cancellation'::text, 'provider-pending'::text, 'event-purchase-refund-%s'::text, 'event-purchase-refund'::text, 'pending'::text)
    $$, :'freePurchaseID', :'paidPurchaseID', :'paidPurchaseID', :'rejectedPaidPurchaseID', :'rejectedPaidPurchaseID'),
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
    'OCG01',
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
