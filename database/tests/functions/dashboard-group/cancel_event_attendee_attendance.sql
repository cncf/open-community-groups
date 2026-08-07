-- Tests canceling confirmed attendee attendance from the group dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(22);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '3a070000-0000-0000-0000-000000000001'
\set approvalRefundAttendeeID '3a070000-0000-0000-0000-00000000001f'
\set approvalRefundID '3a070000-0000-0000-0000-000000000022'
\set approvalRefundPurchaseID '3a070000-0000-0000-0000-000000000020'
\set approvalRefundRequestID '3a070000-0000-0000-0000-000000000021'
\set approvedRequestAttendeeID '3a070000-0000-0000-0000-000000000023'
\set approvedRequestPurchaseID '3a070000-0000-0000-0000-000000000024'
\set approvedRequestRefundRequestID '3a070000-0000-0000-0000-000000000025'
\set attendeeID '3a070000-0000-0000-0000-000000000002'
\set communityID '3a070000-0000-0000-0000-000000000003'
\set conflictingRefundAttendeeID '3a070000-0000-0000-0000-000000000026'
\set conflictingRefundID '3a070000-0000-0000-0000-000000000028'
\set conflictingRefundPurchaseID '3a070000-0000-0000-0000-000000000027'
\set eventCanceledID '3a070000-0000-0000-0000-000000000004'
\set eventCategoryID '3a070000-0000-0000-0000-000000000005'
\set eventID '3a070000-0000-0000-0000-000000000006'
\set eventLimitedID '3a070000-0000-0000-0000-000000000007'
\set eventPaidID '3a070000-0000-0000-0000-000000000008'
\set eventTicketTypeID '3a070000-0000-0000-0000-000000000009'
\set eventTicketedFreeID '3a070000-0000-0000-0000-000000000018'
\set eventUnpublishedID '3a070000-0000-0000-0000-000000000010'
\set freeTicketAttendeeID '3a070000-0000-0000-0000-000000000019'
\set freeTicketPriceWindowID '3a070000-0000-0000-0000-00000000001a'
\set freeTicketPromotedUserID '3a070000-0000-0000-0000-00000000001b'
\set freeTicketPurchaseID '3a070000-0000-0000-0000-00000000001c'
\set freeTicketTypeID '3a070000-0000-0000-0000-00000000001d'
\set groupCategoryID '3a070000-0000-0000-0000-000000000011'
\set groupID '3a070000-0000-0000-0000-000000000012'
\set invalidProviderAttendeeID '3a070000-0000-0000-0000-000000000029'
\set invalidProviderPurchaseID '3a070000-0000-0000-0000-00000000002a'
\set limitedAttendeeID '3a070000-0000-0000-0000-000000000013'
\set paidAttendeeID '3a070000-0000-0000-0000-000000000014'
\set promotedUserID '3a070000-0000-0000-0000-000000000015'
\set purchaseID '3a070000-0000-0000-0000-000000000016'
\set rejectedRequestAttendeeID '3a070000-0000-0000-0000-00000000002b'
\set rejectedRequestPurchaseID '3a070000-0000-0000-0000-00000000002c'
\set rejectedRequestRefundRequestID '3a070000-0000-0000-0000-00000000002d'
\set unknownGroupID '3a070000-0000-0000-0000-000000000017'

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
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Tech', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Users
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values
    ('hash-actor', 'actor@example.com', true, 'Actor', :'actorID', 'actor'),
    (
        'hash-approval-refund',
        'approval-refund@example.com',
        true,
        'Approval Refund',
        :'approvalRefundAttendeeID',
        'approval-refund'
    ),
    (
        'hash-approved-request',
        'approved-request@example.com',
        true,
        'Approved Request',
        :'approvedRequestAttendeeID',
        'approved-request'
    ),
    ('hash-attendee', 'attendee@example.com', true, 'Attendee', :'attendeeID', 'attendee'),
    (
        'hash-conflicting-refund',
        'conflicting-refund@example.com',
        true,
        'Conflicting Refund',
        :'conflictingRefundAttendeeID',
        'conflicting-refund'
    ),
    (
        'hash-free-attendee',
        'free-attendee@example.com',
        true,
        'Free Attendee',
        :'freeTicketAttendeeID',
        'free-attendee'
    ),
    (
        'hash-free-promoted',
        'free-promoted@example.com',
        true,
        'Free Promoted',
        :'freeTicketPromotedUserID',
        'free-promoted'
    ),
    (
        'hash-invalid-provider',
        'invalid-provider@example.com',
        true,
        'Invalid Provider',
        :'invalidProviderAttendeeID',
        'invalid-provider'
    ),
    ('hash-limited', 'limited@example.com', true, 'Limited', :'limitedAttendeeID', 'limited'),
    ('hash-paid', 'paid@example.com', true, 'Paid', :'paidAttendeeID', 'paid'),
    ('hash-promoted', 'promoted@example.com', true, 'Promoted', :'promotedUserID', 'promoted'),
    (
        'hash-rejected-request',
        'rejected-request@example.com',
        true,
        'Rejected Request',
        :'rejectedRequestAttendeeID',
        'rejected-request'
    );

-- Events
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    payment_currency_code,
    published,
    canceled,
    capacity,
    waitlist_enabled,
    starts_at
)
values
    (
        :'eventID',
        'Free Event',
        'free-event',
        'Test free event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        false,
        null,
        false,
        now() + interval '7 days'
    ), (
        :'eventCanceledID',
        'Canceled Event',
        'canceled-event',
        'Test canceled event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        true,
        null,
        false,
        now() + interval '7 days'
    ), (
        :'eventLimitedID',
        'Limited Event',
        'limited-event',
        'Test limited event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        false,
        1,
        true,
        now() + interval '7 days'
    ), (
        :'eventPaidID',
        'Paid Event',
        'paid-event',
        'Test paid event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'USD',
        true,
        false,
        null,
        false,
        now() + interval '7 days'
    ), (
        :'eventTicketedFreeID',
        'Ticketed Free Event',
        'ticketed-free-event',
        'Test ticketed free event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        true,
        false,
        null,
        true,
        now() + interval '7 days'
    ), (
        :'eventUnpublishedID',
        'Unpublished Event',
        'unpublished-event',
        'Test unpublished event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        null,
        false,
        false,
        null,
        false,
        now() + interval '7 days'
    );

-- Ticket types
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values
    (:'eventTicketTypeID', :'eventPaidID', 1, 10, 'Paid admission'),
    (:'freeTicketTypeID', :'eventTicketedFreeID', 1, 1, 'Free admission');

-- Current intrinsic-free price used when the released ticket seat is offered
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'freeTicketPriceWindowID',
    0,
    :'freeTicketTypeID'
);

-- Events without a specialized ticket fixture use a default free tier
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
)
select
    e.event_id,
    gen_random_uuid(),
    1,
    greatest(coalesce(e.capacity, 100), 1),
    'General Admission'
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current free prices for the default ticket tiers
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
)
select 0, gen_random_uuid(), ett.event_ticket_type_id
from event_ticket_type ett
where not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
);

-- Completed purchases linked to the paid and free-ticket attendees
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    payment_provider_id,
    provider_payment_reference
)
values
    (
        :'purchaseID',
        2500,
        'USD',
        :'eventPaidID',
        :'eventTicketTypeID',
        'completed',
        'Paid admission',
        :'paidAttendeeID',

        'stripe',
        'pi_paid_attendance_cancel'
    ),
    (
        :'freeTicketPurchaseID',
        0,
        null,
        :'eventTicketedFreeID',
        :'freeTicketTypeID',
        'completed',
        'Free admission',
        :'freeTicketAttendeeID',

        null,
        null
    ),
    (
        :'approvalRefundPurchaseID',
        2500,
        'USD',
        :'eventPaidID',
        :'eventTicketTypeID',
        'refund-requested',
        'Paid admission',
        :'approvalRefundAttendeeID',

        'stripe',
        'pi_approval_refund'
    ),
    (
        :'approvedRequestPurchaseID',
        2500,
        'USD',
        :'eventPaidID',
        :'eventTicketTypeID',
        'completed',
        'Paid admission',
        :'approvedRequestAttendeeID',

        'stripe',
        'pi_approved_request'
    ),
    (
        :'conflictingRefundPurchaseID',
        2500,
        'USD',
        :'eventPaidID',
        :'eventTicketTypeID',
        'refund-requested',
        'Paid admission',
        :'conflictingRefundAttendeeID',

        'stripe',
        'pi_conflicting_refund'
    ),
    (
        :'invalidProviderPurchaseID',
        2500,
        'USD',
        :'eventPaidID',
        :'eventTicketTypeID',
        'completed',
        'Paid admission',
        :'invalidProviderAttendeeID',

        null,
        null
    ),
    (
        :'rejectedRequestPurchaseID',
        2500,
        'USD',
        :'eventPaidID',
        :'eventTicketTypeID',
        'completed',
        'Paid admission',
        :'rejectedRequestAttendeeID',

        'stripe',
        'pi_rejected_request'
    );

-- Attendees including a checked-in row whose active state must be cleared
insert into event_attendee (checked_in, checked_in_at, event_id, status, user_id)
values
    (true, current_timestamp, :'eventID', 'confirmed', :'attendeeID'),
    (false, null, :'eventPaidID', 'confirmed', :'approvalRefundAttendeeID'),
    (false, null, :'eventPaidID', 'confirmed', :'approvedRequestAttendeeID'),
    (false, null, :'eventPaidID', 'confirmed', :'conflictingRefundAttendeeID'),
    (false, null, :'eventTicketedFreeID', 'confirmed', :'freeTicketAttendeeID'),
    (false, null, :'eventPaidID', 'confirmed', :'invalidProviderAttendeeID'),
    (false, null, :'eventLimitedID', 'confirmed', :'limitedAttendeeID'),
    (true, current_timestamp, :'eventPaidID', 'confirmed', :'paidAttendeeID'),
    (false, null, :'eventPaidID', 'confirmed', :'rejectedRequestAttendeeID');

-- Existing refund requests used by paid cancellation branch tests
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status,

    reviewed_at,
    reviewed_by_user_id
) values
    (
        :'approvalRefundRequestID',
        :'approvalRefundPurchaseID',
        :'approvalRefundAttendeeID',
        'approving',

        current_timestamp,
        :'actorID'
    ),
    (
        :'approvedRequestRefundRequestID',
        :'approvedRequestPurchaseID',
        :'approvedRequestAttendeeID',
        'approved',

        current_timestamp,
        :'actorID'
    ),
    (
        :'rejectedRequestRefundRequestID',
        :'rejectedRequestPurchaseID',
        :'rejectedRequestAttendeeID',
        'rejected',

        current_timestamp,
        :'actorID'
    );

-- Existing durable refunds used by paid cancellation branch tests
insert into event_purchase_refund (
    event_purchase_refund_id,
    amount_minor,
    currency_code,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status,
    terminal_failure,

    event_refund_request_id,
    failure_message,
    initiated_by_user_id,
    provider_refund_id
) values
    (
        :'approvalRefundID',
        2500,
        'USD',
        :'approvalRefundPurchaseID',
        'event-purchase-refund-approval-reuse',
        'refund-request-approval',
        'stripe',
        'provider-failed',
        true,

        :'approvalRefundRequestID',
        'provider refund failed: re_approval_reuse',
        :'actorID',
        're_approval_reuse'
    ),
    (
        :'conflictingRefundID',
        2500,
        'USD',
        :'conflictingRefundPurchaseID',
        'event-purchase-refund-conflicting-kind',
        'event-cancellation',
        'stripe',
        'provider-failed',
        true,

        null,
        'provider refund failed: re_conflicting_kind',
        :'actorID',
        're_conflicting_kind'
    );

-- Waitlist entries
insert into event_waitlist (event_id, user_id, created_at, event_ticket_type_id)
values
    (
        :'eventLimitedID',
        :'promotedUserID',
        now(),
        (select event_ticket_type_id from event_ticket_type where event_id = :'eventLimitedID' limit 1)
    ),
    (
        :'eventTicketedFreeID',
        :'freeTicketPromotedUserID',
        now(),
        :'freeTicketTypeID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel confirmed attendance.
select results_eq(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L)::jsonb $$,
        :'actorID', :'groupID', :'eventID', :'attendeeID'
    ),
    $$ values ('{"cancellation_status": "attendance-canceled"}'::jsonb) $$,
    'Should cancel a confirmed attendance'
);

select results_eq(
    format($$
        select
            attendance_canceled_at is not null,
            attendance_canceled_by_user_id,
            checked_in,
            checked_in_at,
            status
        from event_attendee
        where event_id = %L::uuid
        and user_id = %L::uuid
    $$, :'eventID', :'attendeeID'),
    format($$ values (true, %L::uuid, false, null::timestamptz, 'attendance-canceled'::text) $$, :'actorID'),
    'Should preserve inactive attendee history'
);

-- Should create the expected audit row.
select results_eq(
    $$
        select
            action,
            actor_user_id,
            community_id,
            event_id,
            group_id,
            resource_id,
            resource_type,
            details
        from audit_log
    $$,
    format(
        $$
        values (
            'event_attendee_attendance_canceled',
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'user',
            '{"event_id": "%s", "user_id": "%s"}'::jsonb
        )
        $$,
        :'actorID', :'communityID', :'eventID', :'groupID', :'attendeeID', :'eventID', :'attendeeID'
    ),
    'Should create the expected audit row'
);

-- Should reject canceling missing confirmed attendees.
select throws_ok(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventID', :'attendeeID'
    ),
    'confirmed event attendee not found',
    'Should reject canceling missing confirmed attendance'
);

-- Should reject events outside the selected group.
select throws_ok(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L) $$,
        :'actorID', :'unknownGroupID', :'eventID', :'attendeeID'
    ),
    'event not found or inactive',
    'Should reject events outside the selected group'
);

-- Should queue a full refund while preserving paid attendance
select results_eq(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L)::jsonb $$,
        :'actorID', :'groupID', :'eventPaidID', :'paidAttendeeID'
    ),
    $$ values ('{"cancellation_status": "refund-queued"}'::jsonb) $$,
    'Should queue paid attendee cancellation'
);

-- Should preserve attendance and persist durable refund work
select results_eq(
    format(
        $$
            select
                ep.status,
                ea.status,
                ea.checked_in,
                ea.checked_in_at is not null,
                ea.attendance_canceled_at is null,
                err.status,
                err.requested_by_user_id,
                err.reviewed_by_user_id,
                epr.amount_minor,
                epr.currency_code,
                epr.event_refund_request_id = err.event_refund_request_id,
                epr.kind,
                epr.payment_provider_id,
                epr.status,
                epr.idempotency_key = format(
                    'event-purchase-refund-%%s',
                    ep.event_purchase_id
                )
            from event_purchase ep
            join event_attendee ea
                on ea.event_id = ep.event_id
                and ea.user_id = ep.user_id
            join event_refund_request err using (event_purchase_id)
            join event_purchase_refund epr using (event_purchase_id)
            where ep.event_purchase_id = %L::uuid
        $$,
        :'purchaseID'
    ),
    format(
        $$
            values (
                'refund-requested'::text,
                'confirmed'::text,
                true,
                true,
                true,
                'approving'::text,
                %L::uuid,
                %L::uuid,
                2500::bigint,
                'USD'::text,
                true,
                'attendance-cancellation'::text,
                'stripe'::text,
                'provider-pending'::text,
                true
            )
        $$,
        :'actorID',
        :'actorID'
    ),
    'Should preserve attendance and persist durable refund work'
);

-- Should queue paid cancellation idempotently
select results_eq(
    format(
        $$
            with retry as (
                select cancel_event_attendee_attendance(
                    %L,
                    %L,
                    %L,
                    %L
                )::jsonb as outcome
            )
            select
                retry.outcome,
                (select count(*) from event_purchase_refund where event_purchase_id = %L::uuid),
                (select count(*) from event_refund_request where event_purchase_id = %L::uuid)
            from retry
        $$,
        :'actorID', :'groupID', :'eventPaidID', :'paidAttendeeID', :'purchaseID', :'purchaseID'
    ),
    $$ values ('{"cancellation_status": "refund-queued"}'::jsonb, 1::bigint, 1::bigint) $$,
    'Should queue paid cancellation idempotently'
);

-- Should process and finalize the queued cancellation refund
select lives_ok(
    $$
        do $test$
        declare
            v_refund jsonb;
        begin
            v_refund := claim_event_purchase_refund('stripe');

            perform record_event_purchase_refund_succeeded(
                (v_refund->>'event_purchase_refund_id')::uuid,
                v_refund->>'idempotency_key',
                're_paid_attendance_cancel',
                (v_refund->>'claim_id')::uuid
            );

            perform finalize_event_purchase_refund(
                (v_refund->>'event_purchase_refund_id')::uuid,
                (v_refund->>'claim_id')::uuid,
                '{"event_name": "Paid Event"}'::jsonb
            );
        end;
        $test$
    $$,
    'Should process and finalize the queued cancellation refund'
);

-- Should remove attendance only after refund confirmation
select results_eq(
    format(
        $$
            select
                ep.status,
                ea.status,
                ea.checked_in,
                ea.checked_in_at,
                ea.attendance_canceled_at is not null,
                ea.attendance_canceled_by_user_id,
                err.status,
                epr.status,
                epr.finalized_at is not null,
                exists (
                    select 1
                    from notification n
                    where n.kind = 'event-refund-approved'
                    and n.user_id = ep.user_id
                )
            from event_purchase ep
            join event_attendee ea
                on ea.event_id = ep.event_id
                and ea.user_id = ep.user_id
            join event_refund_request err using (event_purchase_id)
            join event_purchase_refund epr using (event_purchase_id)
            where ep.event_purchase_id = %L::uuid
        $$,
        :'purchaseID'
    ),
    format(
        $$
            values (
                'refunded'::text,
                'attendance-canceled'::text,
                false,
                null::timestamptz,
                true,
                %L::uuid,
                'approved'::text,
                'finalized'::text,
                true,
                true
            )
        $$,
        :'actorID'
    ),
    'Should remove attendance only after refund confirmation'
);

-- Should reuse a compatible refund approval workflow
select results_eq(
    format($$
        with cancellation as (
            select cancel_event_attendee_attendance(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid
            )::jsonb as outcome
        )
        select
            cancellation.outcome,
            (select count(*) from event_purchase_refund where event_purchase_id = %L::uuid),
            (select count(*) from event_refund_request where event_purchase_id = %L::uuid)
        from cancellation
    $$,
        :'actorID',
        :'groupID',
        :'eventPaidID',
        :'approvalRefundAttendeeID',
        :'approvalRefundPurchaseID',
        :'approvalRefundPurchaseID'
    ),
    $$ values ('{"cancellation_status": "refund-queued"}'::jsonb, 1::bigint, 1::bigint) $$,
    'Should reuse a compatible refund approval workflow'
);

-- Should reject an approved request without durable refund work
select throws_ok(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventPaidID', :'approvedRequestAttendeeID'
    ),
    'refund request is not available for attendance cancellation',
    'Should reject an approved request without durable refund work'
);

-- Should reject durable work created for a different refund kind
select throws_ok(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventPaidID', :'conflictingRefundAttendeeID'
    ),
    'event purchase refund already started with different kind',
    'Should reject durable work created for a different refund kind'
);

-- Should reject a paid purchase without provider references
select throws_ok(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventPaidID', :'invalidProviderAttendeeID'
    ),
    'paid purchase is not ready for refund',
    'Should reject a paid purchase without provider references'
);

-- Should promote a rejected request into attendance cancellation work
select results_eq(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L)::jsonb $$,
        :'actorID', :'groupID', :'eventPaidID', :'rejectedRequestAttendeeID'
    ),
    $$ values ('{"cancellation_status": "refund-queued"}'::jsonb) $$,
    'Should promote a rejected request into attendance cancellation work'
);

-- Should persist the promoted request and durable refund work
select results_eq(
    format($$
        select
            err.status,
            epr.kind,
            epr.status
        from event_refund_request err
        join event_purchase_refund epr using (event_purchase_id)
        where err.event_purchase_id = %L::uuid
    $$, :'rejectedRequestPurchaseID'),
    $$ values (
        'approving'::text,
        'attendance-cancellation'::text,
        'provider-pending'::text
    ) $$,
    'Should persist the promoted request and durable refund work'
);

-- Should reconcile a free ticket cancellation into the same tier queue
select results_eq(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L, null)::jsonb $$,
        :'actorID',
        :'groupID',
        :'eventTicketedFreeID',
        :'freeTicketAttendeeID'
    ),
    $$ values ('{"cancellation_status": "attendance-canceled"}'::jsonb) $$,
    'Should cancel free ticket attendance without returning ticket offer recipients'
);

select results_eq(
    format(
        $$
            select
                ea.status,
                ep.status,
                ao.event_ticket_type_id,
                ao.source,
                ao.status,
                not exists (
                    select 1
                    from event_waitlist ew
                    where ew.event_id = %L::uuid
                    and ew.event_ticket_type_id = %L::uuid
                    and ew.user_id = %L::uuid
                )
            from event_attendee ea
            join event_purchase ep
                on ep.event_id = ea.event_id
                and ep.user_id = ea.user_id
            join admission_offer ao
                on ao.event_id = ea.event_id
                and ao.user_id = %L::uuid
            where ea.event_id = %L::uuid
            and ea.user_id = %L::uuid
        $$,
        :'eventTicketedFreeID',
        :'freeTicketTypeID',
        :'freeTicketPromotedUserID',
        :'freeTicketPromotedUserID',
        :'eventTicketedFreeID',
        :'freeTicketAttendeeID'
    ),
    format(
        $$
            values (
                'attendance-canceled'::text,
                'refunded'::text,
                %L::uuid,
                'waitlist'::text,
                'pending'::text,
                true
            )
        $$,
        :'freeTicketTypeID'
    ),
    'Should refund the free purchase and offer the released tier seat'
);

-- Should offer the released seat to a waitlisted user
select results_eq(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L)::jsonb $$,
        :'actorID', :'groupID', :'eventLimitedID', :'limitedAttendeeID'
    ),
    $$ values ('{"cancellation_status": "attendance-canceled"}'::jsonb) $$,
    'Should cancel attendance after offering the released seat'
);

select results_eq(
    format(
        $$
        select
            ao.status,
            not exists (
                select 1
                from event_waitlist ew
                where ew.event_id = %L::uuid
                and ew.user_id = %L::uuid
            )
        from admission_offer ao
        where ao.event_id = %L::uuid
        and ao.user_id = %L::uuid
        $$,
        :'eventLimitedID', :'promotedUserID', :'eventLimitedID', :'promotedUserID'
    ),
    $$ values ('pending'::text, true) $$,
    'Should replace the waitlist entry with an admission offer'
);

-- Should reject unpublished events.
select throws_ok(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventUnpublishedID', :'attendeeID'
    ),
    'event not found or inactive',
    'Should reject unpublished events'
);

-- Should reject canceled events.
select throws_ok(
    format(
        $$ select cancel_event_attendee_attendance(%L, %L, %L, %L) $$,
        :'actorID', :'groupID', :'eventCanceledID', :'attendeeID'
    ),
    'event not found or inactive',
    'Should reject canceled events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
