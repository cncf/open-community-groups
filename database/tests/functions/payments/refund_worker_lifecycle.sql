-- Tests the complete durable refund worker handoff across database functions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(16);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'd2010000-0000-0000-0000-000000000001'
\set buyerID 'd2010000-0000-0000-0000-000000000002'
\set communityID 'd2010000-0000-0000-0000-000000000003'
\set eventCategoryID 'd2010000-0000-0000-0000-000000000004'
\set eventID 'd2010000-0000-0000-0000-000000000005'
\set groupCategoryID 'd2010000-0000-0000-0000-000000000006'
\set groupID 'd2010000-0000-0000-0000-000000000007'
\set purchaseID 'd2010000-0000-0000-0000-000000000008'
\set rejectedBuyerID 'd2010000-0000-0000-0000-000000000011'
\set rejectedEventID 'd2010000-0000-0000-0000-000000000012'
\set rejectedPurchaseID 'd2010000-0000-0000-0000-000000000013'
\set rejectedRefundRequestID 'd2010000-0000-0000-0000-000000000014'
\set rejectedTicketTypeID 'd2010000-0000-0000-0000-000000000015'
\set refundRequestID 'd2010000-0000-0000-0000-000000000009'
\set siteID 'd2010000-0000-0000-0000-000000000016'
\set ticketTypeID 'd2010000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Site settings used to compose the recovery completion notification
insert into site (description, site_id, theme, title)
values (
    'Refund worker lifecycle site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Refund Worker Lifecycle Site'
);

-- Community owning the end-to-end refund lifecycle
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.test/mobile.png',
    'https://example.test/banner.png',
    :'communityID',
    'Community',
    'Community',
    'https://example.test/logo.png',
    'refund-worker-community'
);

-- Event category used by the end-to-end refund event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the end-to-end refund group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the end-to-end refund event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Organizer and buyer participating in the end-to-end refund lifecycle
insert into "user" (auth_hash, email, user_id, username) values
    ('actor', 'actor@example.test', :'actorID', 'actor'),
    ('buyer', 'buyer@example.test', :'buyerID', 'buyer'),
    ('rejected', 'rejected@example.test', :'rejectedBuyerID', 'rejected-buyer');

-- Accepted event manager allowed to complete refund recovery
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'events-manager', :'actorID');

-- Event owning the end-to-end refund purchase
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
    'Event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Event',
    'USD',
    true,
    'event',
    now() + interval '1 day',
    'UTC'
), (
    'Rejected request event',
    :'eventCategoryID',
    :'rejectedEventID',
    'in-person',
    :'groupID',
    'Rejected Request Event',
    'USD',
    true,
    'rejected-request-event',
    now() + interval '2 days',
    'UTC'
);

-- Ticket type referenced by the end-to-end refund purchase
insert into event_ticket_type (event_id, event_ticket_type_id, "order", seats_total, title)
values
    (:'eventID', :'ticketTypeID', 1, 10, 'General admission'),
    (:'rejectedEventID', :'rejectedTicketTypeID', 1, 10, 'General admission');

-- Confirmed attendee whose paid registration will be refunded
insert into event_attendee (checked_in, checked_in_at, event_id, status, user_id)
values
    (true, current_timestamp, :'eventID', 'confirmed', :'buyerID'),
    (true, current_timestamp, :'rejectedEventID', 'confirmed', :'rejectedBuyerID');

-- Paid purchase with an attendee refund request ready for approval
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
    user_id
) values (
    2500,
    'USD',
    :'eventID',
    :'purchaseID',
    :'ticketTypeID',
    'stripe',
    'pi_worker',
    'refund-requested',
    'General admission',
    :'buyerID'
), (
    2500,
    'USD',
    :'rejectedEventID',
    :'rejectedPurchaseID',
    :'rejectedTicketTypeID',
    'stripe',
    'pi_rejected_then_canceled',
    'refund-requested',
    'General admission',
    :'rejectedBuyerID'
);

-- Pending attendee refund request approved by the worker lifecycle
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status
) values (
    :'purchaseID',
    :'refundRequestID',
    :'buyerID',
    'pending'
), (
    :'rejectedPurchaseID',
    :'rejectedRefundRequestID',
    :'rejectedBuyerID',
    'pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should queue an approved refund request for worker processing
select lives_ok(
    format(
        'select queue_event_refund_request_approval(%L, %L, %L, %L)',
        :'actorID', :'groupID', :'purchaseID', 'Approved by organizer'
    ),
    'Should queue an approved refund request for worker processing'
);

-- Should persist worker work and the in-progress review decision
select results_eq(
    format($$
        select epr.kind, epr.status, epr.initiated_by_user_id, err.status
        from event_purchase_refund epr
        join event_refund_request err using (event_refund_request_id)
        where epr.event_purchase_id = %L::uuid
    $$, :'purchaseID'),
    format($$ values (
        'refund-request-approval'::text,
        'provider-pending'::text,
        %L::uuid,
        'approving'::text
    ) $$, :'actorID'),
    'Should persist worker work and the in-progress review decision'
);

-- Should claim the queued provider work
select lives_ok(
    $$select claim_event_purchase_refund('stripe')$$,
    'Should claim the queued provider work'
);

-- Should pin the first processing attempt
select results_eq(
    format($$
        select attempt_count, claim_id is not null, status
        from event_purchase_refund
        where event_purchase_id = %L::uuid
    $$, :'purchaseID'),
    $$ values (1, true, 'processing'::text) $$,
    'Should pin the first processing attempt'
);

-- Should record provider success without releasing the active claim
select is(
    (
        select record_event_purchase_refund_succeeded(
            event_purchase_refund_id,
            idempotency_key,
            're_worker_succeeded',
            claim_id
        )->>'status'
        from event_purchase_refund
        where event_purchase_id = :'purchaseID'
    ),
    'processing',
    'Should record provider success without releasing the active claim'
);

-- Should finalize provider-complete work under the active claim
select lives_ok(
    format(
        $$
            select finalize_event_purchase_refund(
                event_purchase_refund_id,
                claim_id,
                jsonb_build_object('scenario', 'worker-lifecycle')
            )
            from event_purchase_refund
            where event_purchase_id = %L::uuid
        $$,
        :'purchaseID'
    ),
    'Should finalize provider-complete work under the active claim'
);

-- Should finalize purchase, attendee history, and review state together
select results_eq(
    format($$
        select
            ep.status,
            epr.status,
            ea.checked_in,
            ea.status,
            err.status
        from event_purchase ep
        join event_purchase_refund epr using (event_purchase_id)
        join event_refund_request err using (event_purchase_id)
        join event_attendee ea
            on ea.event_id = ep.event_id
            and ea.user_id = ep.user_id
        where ep.event_purchase_id = %L::uuid
    $$, :'purchaseID'),
    $$ values (
        'refunded'::text,
        'finalized'::text,
        false,
        'attendance-canceled'::text,
        'approved'::text
    ) $$,
    'Should finalize purchase, attendee history, and review state together'
);

-- Should atomically enqueue the refund-completed notification
select results_eq(
    format($$
        select n.kind, n.user_id, ntd.data
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-refund-approved'
        and n.user_id = %L::uuid
    $$, :'buyerID'),
    format($$ values (
        'event-refund-approved'::text,
        %L::uuid,
        jsonb_build_object('scenario', 'worker-lifecycle')
    ) $$, :'buyerID'),
    'Should atomically enqueue the refund-completed notification'
);

-- Should write one audit entry for the completed lifecycle
select is(
    (select count(*)::int from audit_log where action = 'event_refunded'),
    1,
    'Should write one audit entry for the completed lifecycle'
);

-- Should reject the second attendee request before canceling its event
select lives_ok(
    format(
        'select reject_event_refund_request(%L, %L, %L, %L)',
        :'actorID', :'groupID', :'rejectedPurchaseID', 'Not eligible before cancellation'
    ),
    'Should reject the second attendee request before canceling its event'
);

-- Should cancel the event and queue its completed purchase for refund
select lives_ok(
    format(
        'select cancel_event(%L, %L, %L)',
        :'actorID', :'groupID', :'rejectedEventID'
    ),
    'Should cancel the event and queue its completed purchase for refund'
);

-- Should preserve rejected history without linking it to cancellation work
select results_eq(
    format($$
        select
            ep.status,
            epr.event_refund_request_id,
            epr.kind,
            epr.status,
            err.status
        from event_purchase ep
        join event_purchase_refund epr using (event_purchase_id)
        join event_refund_request err using (event_purchase_id)
        where ep.event_purchase_id = %L::uuid
    $$, :'rejectedPurchaseID'),
    $$ values (
        'refund-pending'::text,
        null::uuid,
        'event-cancellation'::text,
        'provider-pending'::text,
        'rejected'::text
    ) $$,
    'Should preserve rejected history without linking it to cancellation work'
);

-- Should claim the cancellation refund after the rejected attendee request
select lives_ok(
    $$select claim_event_purchase_refund('stripe')$$,
    'Should claim the cancellation refund after the rejected attendee request'
);

-- Should record a terminal failure for the cancellation refund
select lives_ok(
    format(
        $$
            select record_event_purchase_refund_terminal_failed(
                event_purchase_refund_id,
                idempotency_key,
                're_rejected_then_canceled',
                'Provider refund requires external recovery',
                claim_id
            )
            from event_purchase_refund
            where event_purchase_id = %L::uuid
        $$,
        :'rejectedPurchaseID'
    ),
    'Should record a terminal failure for the cancellation refund'
);

-- Should complete terminal recovery for cancellation with rejected request history
select lives_ok(
    format(
        $$
            select complete_event_purchase_refund_recovery(
                %L::uuid,
                %L::uuid,
                event_purchase_refund_id,
                'external-refund-rejected-then-canceled',
                'Verified external refund',
                '{}'::jsonb
            )
            from event_purchase_refund
            where event_purchase_id = %L::uuid
        $$,
        :'actorID',
        :'groupID',
        :'rejectedPurchaseID'
    ),
    'Should complete terminal recovery for cancellation with rejected request history'
);

-- Should finalize cancellation recovery without rewriting rejected request history
select results_eq(
    format($$
        select
            ep.status,
            epr.finalized_at is not null,
            epr.recovery_completed_at is not null,
            epr.status,
            err.status
        from event_purchase ep
        join event_purchase_refund epr using (event_purchase_id)
        join event_refund_request err using (event_purchase_id)
        where ep.event_purchase_id = %L::uuid
    $$, :'rejectedPurchaseID'),
    $$ values (
        'refunded'::text,
        true,
        true,
        'provider-failed'::text,
        'rejected'::text
    ) $$,
    'Should finalize cancellation recovery without rewriting rejected request history'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
