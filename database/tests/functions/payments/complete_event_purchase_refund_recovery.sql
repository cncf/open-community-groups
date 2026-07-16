-- Tests completing externally resolved terminal provider refunds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(29);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '79530000-0000-0000-0000-000000000001'
\set automaticPurchaseID '79530000-0000-0000-0000-000000000013'
\set automaticRefundID '79530000-0000-0000-0000-000000000014'
\set automaticUserID '79530000-0000-0000-0000-000000000015'
\set communityID '79530000-0000-0000-0000-000000000002'
\set discountCodeID '79530000-0000-0000-0000-000000000026'
\set eventCancellationPurchaseID '79530000-0000-0000-0000-000000000027'
\set eventCancellationRefundID '79530000-0000-0000-0000-000000000028'
\set eventCancellationRefundRequestID '79530000-0000-0000-0000-000000000033'
\set eventCancellationUserID '79530000-0000-0000-0000-000000000029'
\set eventCategoryID '79530000-0000-0000-0000-000000000003'
\set eventID '79530000-0000-0000-0000-000000000004'
\set eventTicketTypeID '79530000-0000-0000-0000-000000000005'
\set groupCategoryID '79530000-0000-0000-0000-000000000006'
\set groupID '79530000-0000-0000-0000-000000000007'
\set invalidPurchaseID '79530000-0000-0000-0000-000000000016'
\set invalidRefundID '79530000-0000-0000-0000-000000000017'
\set invalidUserID '79530000-0000-0000-0000-000000000018'
\set missingRefundID '79530000-0000-0000-0000-000000000008'
\set nonterminalPurchaseID '79530000-0000-0000-0000-000000000030'
\set nonterminalRefundID '79530000-0000-0000-0000-000000000031'
\set nonterminalUserID '79530000-0000-0000-0000-000000000032'
\set organizerPurchaseID '79530000-0000-0000-0000-000000000019'
\set organizerRefundID '79530000-0000-0000-0000-000000000020'
\set organizerRefundRequestID '79530000-0000-0000-0000-000000000021'
\set organizerUserID '79530000-0000-0000-0000-000000000022'
\set priceWindowID '79530000-0000-0000-0000-000000000009'
\set purchaseID '79530000-0000-0000-0000-000000000010'
\set refundID '79530000-0000-0000-0000-000000000011'
\set siteID '79530000-0000-0000-0000-000000000034'
\set unpinnedPurchaseID '79530000-0000-0000-0000-000000000023'
\set unpinnedRefundID '79530000-0000-0000-0000-000000000024'
\set unpinnedUserID '79530000-0000-0000-0000-000000000025'
\set userID '79530000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Site settings used to build recovery completion notifications
insert into site (site_id, description, theme, title)
values (
    :'siteID',
    'Complete refund recovery site',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Complete Refund Recovery Site'
);

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
    'complete-refund-recovery-community',
    'Complete Refund Recovery Community',
    'Test',
    'https://e/banner-mobile.png',
    'https://e/banner.png',
    'https://e/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (
        :'actorUserID',
        'hash-1',
        'recovery-operator@example.com',
        true,
        'recovery-operator'
    ),
    (
        :'automaticUserID',
        'hash-3',
        'automatic-recovery-buyer@example.com',
        true,
        'automatic-recovery-buyer'
    ),
    (
        :'eventCancellationUserID',
        'hash-7',
        'event-cancellation-recovery@example.com',
        true,
        'event-cancellation-recovery'
    ),
    (
        :'invalidUserID',
        'hash-4',
        'invalid-recovery-buyer@example.com',
        true,
        'invalid-recovery-buyer'
    ),
    (
        :'nonterminalUserID',
        'hash-8',
        'nonterminal-recovery@example.com',
        true,
        'nonterminal-recovery'
    ),
    (
        :'organizerUserID',
        'hash-5',
        'organizer-recovery-buyer@example.com',
        true,
        'organizer-recovery-buyer'
    ),
    (
        :'unpinnedUserID',
        'hash-6',
        'unpinned-recovery-buyer@example.com',
        true,
        'unpinned-recovery-buyer'
    ),
    (
        :'userID',
        'hash-2',
        'recovery-buyer@example.com',
        true,
        'recovery-buyer'
    );

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Complete Refund Recovery Group',
    'complete-refund-recovery-group'
);

-- Accepted event manager allowed to complete recovery
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'events-manager', :'actorUserID');

-- Canceled event shared by external recovery scenarios
insert into event (
    canceled,
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    starts_at,
    published,
    published_at
) values (
    true,
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Complete Refund Recovery Event',
    'complete-refund-recovery-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    true,
    now()
);

-- Ticket type
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'eventTicketTypeID',
    :'eventID',
    1,
    10,
    'General admission'
);

-- Price window
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    2500,
    :'eventTicketTypeID'
);

-- App-composed notification payload handed to atomic recovery completion
create temporary table refund_recovery_test_data (
    notification_template_data jsonb not null
);

insert into refund_recovery_test_data
values (
    jsonb_build_object(
        'event', jsonb_build_object('event_id', :'eventID'::text),
        'link', 'https://example.test/complete-refund-recovery-community/group/complete-refund-recovery-group/event/complete-refund-recovery-event',
        'theme', (select theme::jsonb from site limit 1)
    )
);

-- Discount reservation released when the organizer recovery completes
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
    'SAVE5',
    :'eventID',
    'fixed_amount',
    'Save 5'
);

-- Purchase awaiting recovery
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    refunded_at
) values (
    :'purchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'eventID',
    :'eventTicketTypeID',
    'refund-recovery-pending',
    'General admission',
    :'userID',

    current_timestamp
), (
    :'eventCancellationPurchaseID',
    2000,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'eventCancellationUserID',

    null
), (
    :'automaticPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'automaticUserID',

    null
), (
    :'invalidPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'eventID',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'invalidUserID',

    null
), (
    :'nonterminalPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'nonterminalUserID',

    null
), (
    :'organizerPurchaseID',
    2000,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'organizerUserID',

    null
), (
    :'unpinnedPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'eventID',
    :'eventTicketTypeID',
    'refund-pending',
    'General admission',
    :'unpinnedUserID',

    null
);

-- Refund requests awaiting external recovery
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status
) values (
    :'organizerRefundRequestID',
    :'organizerPurchaseID',
    :'organizerUserID',
    'approving'
), (
    :'eventCancellationRefundRequestID',
    :'eventCancellationPurchaseID',
    :'eventCancellationUserID',
    'approving'
);

-- Confirmed attendees exercise automatic preservation and organizer release
insert into event_attendee (event_id, user_id)
values
    (:'eventID', :'automaticUserID'),
    (:'eventID', :'organizerUserID');

-- Attendance already canceled when event-cancellation recovery begins
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values (
    current_timestamp,
    :'actorUserID',
    :'eventID',
    'attendance-canceled',
    :'eventCancellationUserID'
);

-- Terminal provider refunds in each supported or invalid local state
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
    finalized_at,
    provider_refund_id
) values (
    :'refundID',
    2500,
    'USD',
    :'purchaseID',
    'event-purchase-refund-recovery-completion',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-failed',
    true,

    null,
    'destination account is closed: re_failed_123',
    current_timestamp,
    're_failed_123'
), (
    :'eventCancellationRefundID',
    2000,
    'USD',
    :'eventCancellationPurchaseID',
    'event-purchase-refund-event-cancellation-recovery',
    'event-cancellation',
    'stripe',
    'provider-failed',
    true,

    :'eventCancellationRefundRequestID',
    'provider refund failed: re_event_cancellation_failed',
    null,
    're_event_cancellation_failed'
), (
    :'automaticRefundID',
    2500,
    'USD',
    :'automaticPurchaseID',
    'event-purchase-refund-automatic-recovery',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-failed',
    true,

    null,
    'provider refund failed: re_automatic_failed',
    null,
    're_automatic_failed'
), (
    :'invalidRefundID',
    2500,
    'USD',
    :'invalidPurchaseID',
    'event-purchase-refund-invalid-recovery',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-failed',
    true,

    null,
    'provider refund failed: re_invalid_failed',
    null,
    're_invalid_failed'
), (
    :'nonterminalRefundID',
    2500,
    'USD',
    :'nonterminalPurchaseID',
    'event-purchase-refund-nonterminal-recovery',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-failed',
    false,

    null,
    'provider refund failed: re_nonterminal_failed',
    null,
    're_nonterminal_failed'
), (
    :'organizerRefundID',
    2000,
    'USD',
    :'organizerPurchaseID',
    'event-purchase-refund-organizer-recovery',
    'refund-request-approval',
    'stripe',
    'provider-failed',
    true,

    :'organizerRefundRequestID',
    'provider refund failed: re_organizer_failed',
    null,
    're_organizer_failed'
), (
    :'unpinnedRefundID',
    2500,
    'USD',
    :'unpinnedPurchaseID',
    'event-purchase-refund-unpinned-recovery',
    'automatic-unfulfillable-checkout',
    'stripe',
    'provider-failed',
    false,

    null,
    'provider request failed before returning an id',
    null,
    null
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject contradictory provider-pending finalization state
select throws_ok(
    format($$
        update event_purchase_refund
        set status = 'provider-pending'
        where event_purchase_refund_id = %L::uuid
    $$, :'refundID'),
    '23514',
    null,
    'Should reject contradictory provider-pending finalization state'
);

-- Should reject partial recovery evidence
select throws_ok(
    format($$
        update event_purchase_refund
        set recovery_reference = 'bank-transfer-123'
        where event_purchase_refund_id = %L::uuid
    $$, :'refundID'),
    '23514',
    null,
    'Should reject partial recovery evidence'
);

-- Should require an operator
select throws_ok(
    format($$select complete_event_purchase_refund_recovery(
        null,
        %L::uuid,
        %L::uuid,
        'bank-transfer-123',
        'Verified by finance',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'groupID', :'refundID'),
    'actor user id is required',
    'Should require an operator'
);

-- Should require an external recovery reference
select throws_ok(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        ' ',
        'Verified by finance',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'refundID'),
    'recovery reference is required',
    'Should require an external recovery reference'
);

-- Should require a recovery note
select throws_ok(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-123',
        ' ',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'refundID'),
    'recovery note is required',
    'Should require a recovery note'
);

-- Should reject an unknown durable refund
select throws_ok(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-123',
        'Verified by finance',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'missingRefundID'),
    'event purchase refund not found',
    'Should reject an unknown durable refund'
);

-- Should reject a terminal refund outside a recoverable purchase state
select throws_ok(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-invalid',
        'Invalid local state',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'invalidRefundID'),
    'recoverable event purchase refund not found',
    'Should reject a terminal refund outside a recoverable purchase state'
);

-- Should reject a terminal refund without a pinned provider attempt
select throws_ok(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-unpinned',
        'Provider attempt is uncertain',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'unpinnedRefundID'),
    'recoverable event purchase refund not found',
    'Should reject a terminal refund without a pinned provider attempt'
);

-- Should reject a pinned provider result that is not terminal
select throws_ok(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-nonterminal',
        'Provider result remains retryable',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'nonterminalRefundID'),
    'recoverable event purchase refund not found',
    'Should reject a pinned provider result that is not terminal'
);

-- Should preserve a nonterminal provider failure after rejected recovery
select results_eq(
    format($$
        select ep.status, epr.recovery_completed_at, epr.terminal_failure
        from event_purchase ep
        join event_purchase_refund epr using (event_purchase_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'nonterminalRefundID'),
    $$ values ('refund-pending'::text, null::timestamptz, false) $$,
    'Should preserve a nonterminal provider failure after rejected recovery'
);

-- Should preserve invalid states without appending audit entries
select results_eq(
    format($$
        select
            invalid_ep.status,
            invalid_epr.recovery_completed_at is null,
            unpinned_ep.status,
            unpinned_epr.recovery_completed_at is null,
            (
                select count(*)::int
                from audit_log
                where action = 'event_refund_recovery_completed'
            )
        from event_purchase invalid_ep
        join event_purchase_refund invalid_epr using (event_purchase_id)
        cross join event_purchase unpinned_ep
        join event_purchase_refund unpinned_epr
            on unpinned_epr.event_purchase_id = unpinned_ep.event_purchase_id
        where invalid_ep.event_purchase_id = %L::uuid
        and unpinned_ep.event_purchase_id = %L::uuid
    $$, :'invalidPurchaseID', :'unpinnedPurchaseID'),
    $$ values (
        'completed'::text,
        true,
        'refund-pending'::text,
        true,
        0::int
    ) $$,
    'Should preserve invalid states without appending audit entries'
);

-- Should require events write access
select throws_ok(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-automatic',
        'Verified automatic refund',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'automaticUserID', :'groupID', :'automaticRefundID'),
    'events write access is required',
    'Should require events write access'
);

-- Should complete an externally resolved recovery
select results_eq(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        ' bank-transfer-123 ',
        ' Verified by finance ',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'refundID'),
    format($$ values (jsonb_build_object(
        'event_id', %L::uuid,
        'recovered_now', true,
        'user_id', %L::uuid
    )) $$, :'eventID', :'userID'),
    'Should complete an externally resolved recovery'
);

-- Should preserve provider failure and store normalized recovery evidence
select results_eq(
    format($$
        select
            epr.status,
            epr.recovery_completed_at is not null,
            epr.recovery_completed_by_user_id,
            epr.recovery_note,
            epr.recovery_reference,
            ep.status,
            ep.refunded_at is not null
        from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'refundID'),
    format($$ values (
        'provider-failed'::text,
        true,
        %L::uuid,
        'Verified by finance'::text,
        'bank-transfer-123'::text,
        'refunded'::text,
        true
    ) $$, :'actorUserID'),
    'Should preserve provider failure and store normalized recovery evidence'
);

-- Should append the expected event audit entry
select results_eq(
    format($$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            details,
            event_id,
            group_id,
            resource_id,
            resource_type
        from audit_log
        where action = 'event_refund_recovery_completed'
    $$),
    format($$ values (
        'event_refund_recovery_completed'::text,
        %L::uuid,
        'recovery-operator'::text,
        %L::uuid,
        jsonb_build_object(
            'event_purchase_id', %L::uuid,
            'event_purchase_refund_id', %L::uuid,
            'provider_refund_id', 're_failed_123',
            'recovery_note', 'Verified by finance',
            'recovery_reference', 'bank-transfer-123',
            'user_id', %L::uuid
        ),
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'event'::text
    ) $$,
        :'actorUserID',
        :'communityID',
        :'purchaseID',
        :'refundID',
        :'userID',
        :'eventID',
        :'groupID',
        :'eventID'
    ),
    'Should append the expected event audit entry'
);

-- Should treat the same completion as an idempotent retry
select results_eq(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-123',
        'Verified by finance',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'refundID'),
    format($$ values (jsonb_build_object(
        'event_id', %L::uuid,
        'recovered_now', false,
        'user_id', %L::uuid
    )) $$, :'eventID', :'userID'),
    'Should treat the same completion as an idempotent retry'
);

-- Should keep a single audit entry after an idempotent retry
select is(
    (
        select count(*)
        from audit_log
        where action = 'event_refund_recovery_completed'
    ),
    1::bigint,
    'Should keep a single audit entry after an idempotent retry'
);

-- Should reject conflicting recovery evidence
select throws_ok(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-456',
        'Different evidence',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'refundID'),
    'refund recovery already completed with different evidence',
    'Should reject conflicting recovery evidence'
);

-- Should preserve the original evidence after a conflicting retry
select results_eq(
    format($$
        select recovery_note, recovery_reference
        from event_purchase_refund
        where event_purchase_refund_id = %L::uuid
    $$, :'refundID'),
    $$ values (
        'Verified by finance'::text,
        'bank-transfer-123'::text
    ) $$,
    'Should preserve the original evidence after a conflicting retry'
);

-- Should require app-composed notification data before local finalization
select throws_ok(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-automatic',
        'Verified automatic refund',
        null
    )$$, :'actorUserID', :'groupID', :'automaticRefundID'),
    'refund notification template data is required',
    'Should require app-composed notification data before local finalization'
);

-- Should complete a terminal automatic refund before local finalization
select results_eq(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-automatic',
        'Verified automatic refund',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'automaticRefundID'),
    format($$ values (jsonb_build_object(
        'event_id', %L::uuid,
        'recovered_now', true,
        'user_id', %L::uuid
    )) $$, :'eventID', :'automaticUserID'),
    'Should complete a terminal automatic refund before local finalization'
);

-- Should finalize the automatic refund while preserving its provider failure
select results_eq(
    format($$
        select
            epr.finalized_at is not null,
            epr.recovery_reference,
            epr.status,
            ep.refunded_at is not null,
            ep.status,
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
                and user_id = %L::uuid
            )
        from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'eventID', :'automaticUserID', :'automaticRefundID'),
    $$ values (
        true,
        'bank-transfer-automatic'::text,
        'provider-failed'::text,
        true,
        'refunded'::text,
        1::int
    ) $$,
    'Should finalize the automatic refund while preserving its provider failure and attendee'
);

-- Should complete a terminal organizer refund converted by event cancellation
select results_eq(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-organizer',
        'Verified organizer refund',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'organizerRefundID'),
    format($$ values (jsonb_build_object(
        'event_id', %L::uuid,
        'recovered_now', true,
        'user_id', %L::uuid
    )) $$, :'eventID', :'organizerUserID'),
    'Should complete a terminal organizer refund after event cancellation'
);

-- Should finalize the organizer request and release its attendee
select results_eq(
    format($$
        select
            epr.finalized_at is not null,
            epr.status,
            ep.refunded_at is not null,
            ep.status,
            err.review_note,
            err.reviewed_at is not null,
            err.reviewed_by_user_id,
            err.status,
            (
                select available
                from event_discount_code
                where event_discount_code_id = %L::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
                and user_id = %L::uuid
                and status = 'attendance-canceled'
            )
        from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        join event_refund_request err using (event_purchase_id)
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'discountCodeID', :'eventID', :'organizerUserID', :'organizerRefundID'),
    format($$ values (
        true,
        'provider-failed'::text,
        true,
        'refunded'::text,
        'Verified organizer refund'::text,
        true,
        %L::uuid,
        'approved'::text,
        1,
        1::int
    ) $$, :'actorUserID'),
    'Should finalize the organizer request and preserve canceled attendee history'
);

-- Should complete a terminal event-cancellation refund before local finalization
select results_eq(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-event-cancellation',
        'Verified event cancellation refund',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'eventCancellationRefundID'),
    format($$ values (jsonb_build_object(
        'event_id', %L::uuid,
        'recovered_now', true,
        'user_id', %L::uuid
    )) $$, :'eventID', :'eventCancellationUserID'),
    'Should complete a terminal event-cancellation refund before local finalization'
);

-- Should finalize event-cancellation purchase and recovery state
select results_eq(
    format($$
        select
            ea.attendance_canceled_by_user_id,
            ea.status,
            ep.refunded_at is not null,
            ep.status,
            epr.finalized_at is not null,
            epr.recovery_completed_at is not null,
            epr.recovery_completed_by_user_id,
            epr.status,
            err.reviewed_at is not null,
            err.reviewed_by_user_id,
            err.status,
            (
                select available
                from event_discount_code
                where event_discount_code_id = %L::uuid
            )
        from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        join event_attendee ea
            on ea.event_id = ep.event_id
            and ea.user_id = ep.user_id
        join event_refund_request err
            on err.event_refund_request_id = epr.event_refund_request_id
        where epr.event_purchase_refund_id = %L::uuid
    $$, :'discountCodeID', :'eventCancellationRefundID'),
    format($$ values (
        %L::uuid,
        'attendance-canceled'::text,
        true,
        'refunded'::text,
        true,
        true,
        %L::uuid,
        'provider-failed'::text,
        true,
        %L::uuid,
        'approved'::text,
        2
    ) $$, :'actorUserID', :'actorUserID', :'actorUserID'),
    'Should finalize event cancellation request, purchase, discount, and recovery state'
);

-- Should enqueue one completion notification with the event context
select results_eq(
    format($$
        select
            n.kind,
            n.user_id,
            ntd.data->'event'->>'event_id',
            ntd.data->>'link',
            ntd.data->'theme'
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-refund-approved'
        and n.user_id = %L::uuid
    $$, :'eventCancellationUserID'),
    format($$
        select
            'event-refund-approved'::text,
            %L::uuid,
            %L::text,
            'https://example.test/complete-refund-recovery-community/group/complete-refund-recovery-group/event/complete-refund-recovery-event'::text,
            (select theme::jsonb from site limit 1)
    $$, :'eventCancellationUserID', :'eventID'),
    'Should enqueue one completion notification with the event context'
);

-- Should treat the event-cancellation recovery replay as idempotent
select results_eq(
    format($$select complete_event_purchase_refund_recovery(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'bank-transfer-event-cancellation',
        'Verified event cancellation refund',
        (select notification_template_data from refund_recovery_test_data)
    )$$, :'actorUserID', :'groupID', :'eventCancellationRefundID'),
    format($$ values (jsonb_build_object(
        'event_id', %L::uuid,
        'recovered_now', false,
        'user_id', %L::uuid
    )) $$, :'eventID', :'eventCancellationUserID'),
    'Should treat the event-cancellation recovery replay as idempotent'
);

-- Should keep one completion notification after the recovery replay
select is(
    (
        select count(*)
        from notification
        where kind = 'event-refund-approved'
        and user_id = :'eventCancellationUserID'
    ),
    1::bigint,
    'Should keep one completion notification after the recovery replay'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
