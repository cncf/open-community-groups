-- Tests local finalization after a provider refund succeeds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(15);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'd4060000-0000-0000-0000-000000000001'
\set communityID 'd4060000-0000-0000-0000-000000000002'
\set discountCodeID 'd4060000-0000-0000-0000-000000000003'
\set eventCategoryID 'd4060000-0000-0000-0000-000000000004'
\set eventID 'd4060000-0000-0000-0000-000000000005'
\set groupCategoryID 'd4060000-0000-0000-0000-000000000006'
\set groupID 'd4060000-0000-0000-0000-000000000007'
\set happyClaimID 'd4060000-0000-0000-0000-000000000008'
\set happyPurchaseID 'd4060000-0000-0000-0000-000000000009'
\set happyRefundID 'd4060000-0000-0000-0000-000000000010'
\set happyRequestID 'd4060000-0000-0000-0000-000000000011'
\set happyUserID 'd4060000-0000-0000-0000-000000000012'
\set incompleteClaimID 'd4060000-0000-0000-0000-000000000013'
\set incompletePurchaseID 'd4060000-0000-0000-0000-000000000014'
\set incompleteRefundID 'd4060000-0000-0000-0000-000000000015'
\set incompleteUserID 'd4060000-0000-0000-0000-000000000016'
\set missingRefundID 'd4060000-0000-0000-0000-000000000017'
\set questionsClaimID 'd4060000-0000-0000-0000-000000000018'
\set questionsPurchaseID 'd4060000-0000-0000-0000-000000000019'
\set questionsRefundID 'd4060000-0000-0000-0000-000000000020'
\set questionsUserID 'd4060000-0000-0000-0000-000000000021'
\set rejectedClaimID 'd4060000-0000-0000-0000-000000000028'
\set rejectedPurchaseID 'd4060000-0000-0000-0000-000000000029'
\set rejectedRefundID 'd4060000-0000-0000-0000-000000000030'
\set rejectedRequestID 'd4060000-0000-0000-0000-000000000031'
\set rejectedUserID 'd4060000-0000-0000-0000-000000000032'
\set staleClaimID 'd4060000-0000-0000-0000-000000000022'
\set stalePurchaseID 'd4060000-0000-0000-0000-000000000023'
\set staleRefundID 'd4060000-0000-0000-0000-000000000024'
\set staleUserID 'd4060000-0000-0000-0000-000000000025'
\set ticketTypeID 'd4060000-0000-0000-0000-000000000026'
\set wrongClaimID 'd4060000-0000-0000-0000-000000000027'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the finalization fixtures
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
    'finalize-refund-community'
);

-- Event category used by the finalization event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the finalization group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the finalization event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Users covering organizer, attendee-request, automatic, incomplete, rejected, and stale claims
insert into "user" (auth_hash, email, user_id, username) values
    ('actor', 'actor@example.test', :'actorID', 'actor'),
    ('happy', 'happy@example.test', :'happyUserID', 'happy'),
    ('incomplete', 'incomplete@example.test', :'incompleteUserID', 'incomplete'),
    ('questions', 'questions@example.test', :'questionsUserID', 'questions'),
    ('rejected', 'rejected@example.test', :'rejectedUserID', 'rejected'),
    ('stale', 'stale@example.test', :'staleUserID', 'stale');

-- Event owning every finalization purchase
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    slug,
    timezone
) values (
    'Event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Event',
    'USD',
    'event',
    'UTC'
);

-- Ticket type referenced by every finalization purchase
insert into event_ticket_type (event_id, event_ticket_type_id, "order", seats_total, title)
values (:'eventID', :'ticketTypeID', 1, 100, 'General admission');

-- Discount reservation released by successful attendee-request finalization
insert into event_discount_code (
    amount_minor,
    available,
    available_override_active,
    code,
    event_discount_code_id,
    event_id,
    kind,
    title
) values (
    500,
    0,
    true,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    'fixed_amount',
    'Save 5'
);

-- Purchases covering successful, automatic, incomplete, rejected, and stale finalization
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    payment_provider_id,
    provider_payment_reference
) values
    (2500, 'USD', :'eventID', :'happyPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'happyUserID', 500, 'SAVE5', :'discountCodeID', 'stripe', 'pi_happy'),
    (2500, 'USD', :'eventID', :'incompletePurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'incompleteUserID', 0, null, null, 'stripe', 'pi_incomplete'),
    (2000, 'USD', :'eventID', :'questionsPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'questionsUserID', 500, 'SAVE5', :'discountCodeID', 'stripe', 'pi_questions'),
    (2500, 'USD', :'eventID', :'rejectedPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'rejectedUserID', 0, null, null, 'stripe', 'pi_rejected'),
    (2500, 'USD', :'eventID', :'stalePurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'staleUserID', 0, null, null, 'stripe', 'pi_stale');

-- Attendee rows removed from active capacity only after successful finalization
insert into event_attendee (checked_in, checked_in_at, event_id, status, user_id) values
    (true, current_timestamp, :'eventID', 'confirmed', :'happyUserID'),
    (false, null, :'eventID', 'confirmed', :'incompleteUserID'),
    (false, null, :'eventID', 'registration-questions-pending', :'questionsUserID'),
    (false, null, :'eventID', 'confirmed', :'staleUserID');

-- Refund requests covering approving and rejected decision history
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status,

    review_note,
    reviewed_at,
    reviewed_by_user_id
) values
    (
        :'happyPurchaseID',
        :'happyRequestID',
        :'happyUserID',
        'approving',
        null,
        null,
        null
    ),
    (
        :'rejectedPurchaseID',
        :'rejectedRequestID',
        :'rejectedUserID',
        'rejected',
        'Outside policy',
        current_timestamp,
        :'actorID'
    );

-- Claimed refund rows covering complete, incomplete, automatic, rejected, and stale claims
insert into event_purchase_refund (
    amount_minor,
    attempt_count,
    claim_id,
    claimed_at,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    idempotency_key,
    initiated_by_user_id,
    kind,
    payment_provider_id,
    review_note,
    status,

    event_refund_request_id,
    provider_refund_id,
    provider_refunded_at
) values
    (2500, 1, :'happyClaimID', current_timestamp, 'USD', :'happyPurchaseID', :'happyRefundID', 'refund-happy', :'actorID', 'refund-request-approval', 'stripe', 'Approved by organizer', 'processing', :'happyRequestID', 're_happy', current_timestamp),
    (2500, 1, :'incompleteClaimID', current_timestamp, 'USD', :'incompletePurchaseID', :'incompleteRefundID', 'refund-incomplete', :'actorID', 'event-cancellation', 'stripe', null, 'processing', null, null, null),
    (2000, 1, :'questionsClaimID', current_timestamp, 'USD', :'questionsPurchaseID', :'questionsRefundID', 'refund-questions', null, 'automatic-unfulfillable-checkout', 'stripe', null, 'processing', null, 're_questions', current_timestamp),
    (2500, 1, :'rejectedClaimID', current_timestamp, 'USD', :'rejectedPurchaseID', :'rejectedRefundID', 'refund-rejected', :'actorID', 'event-cancellation', 'stripe', null, 'processing', :'rejectedRequestID', 're_rejected', current_timestamp),
    (2500, 1, :'staleClaimID', current_timestamp, 'USD', :'stalePurchaseID', :'staleRefundID', 'refund-stale', :'actorID', 'event-cancellation', 'stripe', null, 'processing', null, 're_stale', current_timestamp);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a missing durable refund
select throws_ok(
    format(
        'select finalize_event_purchase_refund(%L::uuid, %L::uuid, %L::jsonb)',
        :'missingRefundID', :'wrongClaimID', '{}'
    ),
    'event purchase refund not found',
    'Should reject a missing durable refund'
);

-- Should reject a provider-incomplete refund
select throws_ok(
    format(
        'select finalize_event_purchase_refund(%L::uuid, %L::uuid, %L::jsonb)',
        :'incompleteRefundID', :'incompleteClaimID', '{}'
    ),
    'event purchase refund claim is not provider-complete',
    'Should reject a provider-incomplete refund'
);

-- Should reject a stale worker claim
select throws_ok(
    format(
        'select finalize_event_purchase_refund(%L::uuid, %L::uuid, %L::jsonb)',
        :'staleRefundID', :'wrongClaimID', '{}'
    ),
    'event purchase refund claim is not provider-complete',
    'Should reject a stale worker claim'
);

-- Should require notification data before mutating provider-complete work
select throws_ok(
    format(
        'select finalize_event_purchase_refund(%L::uuid, %L::uuid, null::jsonb)',
        :'happyRefundID', :'happyClaimID'
    ),
    'refund notification template data is required',
    'Should require notification data before mutating provider-complete work'
);

-- Should leave refund lifecycle and outbox state unchanged without notification data
select results_eq(
    format($$
        select
            ep.status,
            ea.status,
            epr.status,
            count(n.notification_id)::int
        from event_purchase ep
        join event_attendee ea
            on ea.event_id = ep.event_id
            and ea.user_id = ep.user_id
        join event_purchase_refund epr using (event_purchase_id)
        left join notification n on n.user_id = ep.user_id
        where ep.event_purchase_id = %L::uuid
        group by ep.status, ea.status, epr.status
    $$, :'happyPurchaseID'),
    $$ values (
        'refund-pending'::text,
        'confirmed'::text,
        'processing'::text,
        0
    ) $$,
    'Should leave refund lifecycle and outbox state unchanged without notification data'
);

-- Should finalize provider-complete attendee-request work
select lives_ok(
    format(
        $$
            select finalize_event_purchase_refund(
                %L::uuid,
                %L::uuid,
                jsonb_build_object('scenario', 'happy')
            )
        $$,
        :'happyRefundID',
        :'happyClaimID'
    ),
    'Should finalize provider-complete attendee-request work'
);

-- Should finalize purchase, attendance, review, discount, and claim state atomically
select results_eq(
    format($$
        select
            ep.status,
            ep.refunded_at is not null,
            ea.attendance_canceled_at is not null,
            ea.attendance_canceled_by_user_id,
            ea.checked_in,
            ea.checked_in_at,
            ea.status,
            err.review_note,
            err.reviewed_at is not null,
            err.reviewed_by_user_id,
            err.status,
            edc.available,
            epr.claim_id,
            epr.claimed_at,
            epr.finalized_at is not null,
            epr.status
        from event_purchase ep
        join event_attendee ea
            on ea.event_id = ep.event_id
            and ea.user_id = ep.user_id
        join event_discount_code edc using (event_discount_code_id)
        join event_purchase_refund epr using (event_purchase_id)
        join event_refund_request err using (event_purchase_id)
        where ep.event_purchase_id = %L::uuid
    $$, :'happyPurchaseID'),
    format($$ values (
        'refunded'::text,
        true,
        true,
        %L::uuid,
        false,
        null::timestamptz,
        'attendance-canceled'::text,
        'Approved by organizer'::text,
        true,
        %L::uuid,
        'approved'::text,
        1,
        null::uuid,
        null::timestamptz,
        true,
        'finalized'::text
    ) $$, :'actorID', :'actorID'),
    'Should finalize purchase, attendance, review, discount, and claim state atomically'
);

-- Should atomically enqueue the supplied completion notification
select results_eq(
    format($$
        select n.kind, n.user_id, ntd.data
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-refund-approved'
        and n.user_id = %L::uuid
    $$, :'happyUserID'),
    format($$ values (
        'event-refund-approved'::text,
        %L::uuid,
        jsonb_build_object('scenario', 'happy')
    ) $$, :'happyUserID'),
    'Should atomically enqueue the supplied completion notification'
);

-- Should append the expected refund audit entry
select results_eq(
    format($$
        select action, actor_user_id, community_id, event_id, group_id, resource_id, resource_type, details
        from audit_log
        where action = 'event_refunded'
        and event_id = %L::uuid
    $$, :'eventID'),
    format($$ values (
        'event_refunded'::text,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'event'::text,
        jsonb_build_object(
            'event_purchase_id', %L::uuid,
            'kind', 'refund-request-approval',
            'provider_refund_id', 're_happy',
            'user_id', %L::uuid
        )
    ) $$, :'actorID', :'communityID', :'eventID', :'groupID', :'eventID', :'happyPurchaseID', :'happyUserID'),
    'Should append the expected refund audit entry'
);

-- Should treat finalized work as an idempotent replay
select lives_ok(
    format(
        $$
            select finalize_event_purchase_refund(
                %L::uuid,
                %L::uuid,
                jsonb_build_object('scenario', 'replay')
            )
        $$,
        :'happyRefundID',
        :'happyClaimID'
    ),
    'Should treat finalized work as an idempotent replay'
);

-- Should keep one audit and notification entry after an idempotent replay
select results_eq(
    $$
        select
            (select count(*)::int from audit_log where action = 'event_refunded'),
            (
                select count(*)::int
                from notification
                where kind = 'event-refund-approved'
            )
    $$,
    $$ values (1, 1) $$,
    'Should keep one audit and notification entry after an idempotent replay'
);

-- Should finalize a pending-questions attendee without an initiating actor
select lives_ok(
    format(
        $$
            select finalize_event_purchase_refund(
                %L::uuid,
                %L::uuid,
                jsonb_build_object('scenario', 'questions')
            )
        $$,
        :'questionsRefundID',
        :'questionsClaimID'
    ),
    'Should finalize a pending-questions attendee without an initiating actor'
);

-- Should preserve nullable cancellation ownership without releasing its discount twice
select results_eq(
    format($$
        select
            ea.attendance_canceled_at is not null,
            ea.attendance_canceled_by_user_id,
            ea.status,
            edc.available
        from event_attendee ea
        join event_purchase ep
            on ep.event_id = ea.event_id
            and ep.user_id = ea.user_id
        join event_discount_code edc using (event_discount_code_id)
        where ea.event_id = %L::uuid
        and ea.user_id = %L::uuid
    $$, :'eventID', :'questionsUserID'),
    $$ values (true, null::uuid, 'attendance-canceled'::text, 1) $$,
    'Should preserve automatic refund cancellation ownership and released discount inventory'
);

-- Should finalize an event cancellation without rewriting a rejected request
select lives_ok(
    format(
        $$
            select finalize_event_purchase_refund(
                %L::uuid,
                %L::uuid,
                jsonb_build_object('scenario', 'rejected')
            )
        $$,
        :'rejectedRefundID',
        :'rejectedClaimID'
    ),
    'Should finalize an event cancellation with rejected request history'
);

-- Should preserve the rejected decision after the purchase is refunded
select results_eq(
    format($$
        select
            ep.status,
            epr.status,
            err.review_note,
            err.reviewed_at is not null,
            err.reviewed_by_user_id,
            err.status
        from event_purchase ep
        join event_purchase_refund epr using (event_purchase_id)
        join event_refund_request err using (event_purchase_id)
        where ep.event_purchase_id = %L::uuid
    $$, :'rejectedPurchaseID'),
    format($$ values (
        'refunded'::text,
        'finalized'::text,
        'Outside policy'::text,
        true,
        %L::uuid,
        'rejected'::text
    ) $$, :'actorID'),
    'Should preserve the rejected decision after the purchase is refunded'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
