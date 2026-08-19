-- Tests the group dashboard purchase refund workflow list.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'd4100000-0000-0000-0000-000000000001'
\set creditNoteID 'd4100000-0000-0000-0000-000000000024'
\set eventCategoryID 'd4100000-0000-0000-0000-000000000002'
\set eventID 'd4100000-0000-0000-0000-000000000003'
\set event2ID 'd4100000-0000-0000-0000-000000000004'
\set feeAdjustmentID 'd4100000-0000-0000-0000-000000000025'
\set groupCategoryID 'd4100000-0000-0000-0000-000000000005'
\set groupID 'd4100000-0000-0000-0000-000000000006'
\set missingGroupID 'd4100000-0000-0000-0000-000000000007'
\set needsPurchaseID 'd4100000-0000-0000-0000-000000000008'
\set needsRequestID 'd4100000-0000-0000-0000-000000000009'
\set needsUserID 'd4100000-0000-0000-0000-000000000010'
\set refundedPurchaseID 'd4100000-0000-0000-0000-000000000011'
\set refundedRefundID 'd4100000-0000-0000-0000-000000000012'
\set refundedUserID 'd4100000-0000-0000-0000-000000000013'
\set rejectedPurchaseID 'd4100000-0000-0000-0000-000000000014'
\set rejectedRequestID 'd4100000-0000-0000-0000-000000000015'
\set rejectedUserID 'd4100000-0000-0000-0000-000000000016'
\set retryPurchaseID 'd4100000-0000-0000-0000-000000000017'
\set retryRefundID 'd4100000-0000-0000-0000-000000000018'
\set retryUserID 'd4100000-0000-0000-0000-000000000019'
\set ticketTypeID 'd4100000-0000-0000-0000-000000000020'
\set ticketType2ID 'd4100000-0000-0000-0000-000000000021'
\set waitingPurchaseID 'd4100000-0000-0000-0000-000000000022'
\set waitingUserID 'd4100000-0000-0000-0000-000000000023'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the refund list fixtures
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
    'refund-list-community'
);

-- Event category used by the refund list events
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the refund list group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the refund history
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Users representing every operational view
insert into "user" (auth_hash, email, name, photo_url, user_id, username) values
    (
        'needs',
        'requester@example.test',
        'Requesting Attendee',
        'https://example.test/requester.png',
        :'needsUserID',
        'requester'
    ),
    ('refunded', 'refunded@example.test', null, null, :'refundedUserID', 'refunded'),
    ('rejected', 'rejected@example.test', null, null, :'rejectedUserID', 'rejected'),
    ('retry', 'retry@example.test', null, null, :'retryUserID', 'retry'),
    ('waiting', 'waiting@example.test', null, null, :'waitingUserID', 'waiting');

-- Events represented in the group refund history
insert into event (
    canceled,
    deleted,
    deleted_at,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    slug,
    timezone
) values
    (
        true,
        false,
        null,
        'Primary event',
        :'eventCategoryID',
        :'eventID',
        'in-person',
        :'groupID',
        'Primary event',
        'USD',
        'primary-event',
        'UTC'
    ),
    (
        false,
        true,
        '2024-02-01 00:00:00+00',
        'Historical event',
        :'eventCategoryID',
        :'event2ID',
        'in-person',
        :'groupID',
        'Historical event',
        'USD',
        'historical-event',
        'UTC'
    );

-- Ticket types referenced by the refund purchases
insert into event_ticket_type (event_id, event_ticket_type_id, "order", seats_total, title)
values
    (:'eventID', :'ticketTypeID', 1, 100, 'General admission'),
    (:'event2ID', :'ticketType2ID', 1, 100, 'Workshop');

-- Purchases covering review, retry, live checkout, refunded, and rejected states
insert into event_purchase (
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    updated_at,
    user_id,

    payment_provider_id,
    provider_checkout_session_id,
    provider_payment_reference,

    charge_model,
    connected_seller_id,
    final_platform_fee_amount_minor,
    provider_charge_id,
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
    fixture.created_at,
    fixture.currency_code,
    fixture.event_id,
    fixture.event_purchase_id,
    fixture.event_ticket_type_id,
    fixture.status,
    fixture.ticket_title,
    fixture.updated_at,
    fixture.user_id,
    'stripe',
    coalesce(fixture.provider_checkout_session_id, 'cs_' || fixture.event_purchase_id),
    fixture.provider_payment_reference,

    'direct-charge',
    'acct_group_refunds_test',
    case when fixture.status <> 'pending' then 0 end,
    case when fixture.status <> 'pending' then 'ch_' || fixture.event_purchase_id end,
    'acct_group_refunds_test',
    case
        when fixture.status = 'pending' then null
        when fixture.event_purchase_id = :'needsPurchaseID'::uuid then 2750
        else fixture.amount_minor
    end,
    '{}'::jsonb,
    case when fixture.status <> 'pending' then fixture.amount_minor end,
    case
        when fixture.status = 'pending' then null
        when fixture.event_purchase_id = :'needsPurchaseID'::uuid then 250
        else 0
    end,
    case
        when fixture.event_purchase_id = :'needsPurchaseID'::uuid then 'exclusive'
        else 'inclusive'
    end,
    'manual',
    'professional-event-admission',
    '{}'::jsonb
from (
    values
        (2500, '2024-01-01 00:00:00+00'::timestamptz, 'USD', :'eventID'::uuid, :'needsPurchaseID'::uuid, :'ticketTypeID'::uuid, 'refund-requested', 'General admission', '2024-01-01 01:00:00+00'::timestamptz, :'needsUserID'::uuid, null::text, 'pi_needs'),
        (2500, '2024-01-02 00:00:00+00'::timestamptz, 'USD', :'eventID'::uuid, :'retryPurchaseID'::uuid, :'ticketTypeID'::uuid, 'refund-pending', 'General admission', '2024-01-02 01:00:00+00'::timestamptz, :'retryUserID'::uuid, null::text, 'pi_retry'),
        (2500, '2024-01-03 00:00:00+00'::timestamptz, 'USD', :'eventID'::uuid, :'waitingPurchaseID'::uuid, :'ticketTypeID'::uuid, 'pending', 'General admission', '2024-01-03 01:00:00+00'::timestamptz, :'waitingUserID'::uuid, 'cs_waiting', null),
        (5000, '2024-01-04 00:00:00+00'::timestamptz, 'USD', :'event2ID'::uuid, :'refundedPurchaseID'::uuid, :'ticketType2ID'::uuid, 'refunded', 'Workshop', '2024-01-04 01:00:00+00'::timestamptz, :'refundedUserID'::uuid, null::text, 'pi_refunded'),
        (2500, '2024-01-05 00:00:00+00'::timestamptz, 'USD', :'eventID'::uuid, :'rejectedPurchaseID'::uuid, :'ticketTypeID'::uuid, 'completed', 'General admission', '2024-01-05 01:00:00+00'::timestamptz, :'rejectedUserID'::uuid, null::text, 'pi_rejected')
) as fixture(
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    updated_at,
    user_id,
    provider_checkout_session_id,
    provider_payment_reference
);

-- Attendee requests represented in needs-review and completed history
insert into event_refund_request (
    created_at,
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    requested_reason,
    review_note,
    status,
    updated_at
) values
    (
        '2024-01-01 02:00:00+00',
        :'needsPurchaseID',
        :'needsRequestID',
        :'needsUserID',
        'Unable to attend',
        null,
        'pending',
        '2024-01-01 03:00:00+00'
    ),
    (
        '2024-01-05 02:00:00+00',
        :'rejectedPurchaseID',
        :'rejectedRequestID',
        :'rejectedUserID',
        null,
        'Outside policy',
        'rejected',
        '2024-01-05 03:00:00+00'
    );

-- Durable jobs represented in retryable and completed history
insert into event_purchase_refund (
    amount_minor,
    attempt_count,
    created_at,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_provider_id,
    status,
    terminal_failure,
    updated_at,

    failure_message,
    finalized_at,
    provider_refund_id
) values
    (
        2500,
        10,
        '2024-01-02 02:00:00+00',
        'USD',
        :'retryPurchaseID',
        :'retryRefundID',
        'refund-retry',
        'event-cancellation',
        '2024-01-02 04:00:00+00',
        'stripe',
        'provider-pending',
        false,
        '2024-01-02 03:00:00+00',
        null,
        null,
        're_retry'
    ),
    (
        5000,
        1,
        '2024-01-04 02:00:00+00',
        'USD',
        :'refundedPurchaseID',
        :'refundedRefundID',
        'refund-completed',
        'automatic-unfulfillable-checkout',
        '2024-01-04 02:00:00+00',
        'stripe',
        'finalized',
        false,
        '2024-01-04 03:00:00+00',
        null,
        '2024-01-04 03:00:00+00',
        're_refunded'
    );

-- Exhausted application-fee work requiring operator action
insert into event_purchase_application_fee_adjustment (
    amount_minor,
    attempt_count,
    event_purchase_application_fee_adjustment_id,
    event_purchase_id,
    failure_message,
    idempotency_key,
    kind,
    status,
    updated_at
) values (
    25,
    10,
    :'feeAdjustmentID',
    :'retryPurchaseID',
    'Application-fee request failed',
    'refund-list-fee-adjustment',
    'tax-reconciliation',
    'failed',
    '2024-01-02 05:00:00+00'
);

-- Exhausted credit-note work requiring operator action
insert into event_purchase_credit_note (
    amount_minor,
    attempt_count,
    currency_code,
    event_purchase_credit_note_id,
    event_purchase_refund_id,
    failure_message,
    idempotency_key,
    payment_provider_id,
    provider_object_account_id,
    status,
    tax_amount_minor,
    updated_at
) values (
    2500,
    10,
    'USD',
    :'creditNoteID',
    :'retryRefundID',
    'Credit-note request failed',
    'refund-list-credit-note',
    'stripe',
    'acct_group_refunds_test',
    'failed',
    0,
    '2024-01-02 06:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should default to unfinished refund work
select is(
    (
        list_group_refunds(
            :'groupID'::uuid,
            '{"limit": 50, "offset": 0}'::jsonb
        )->>'total'
    )::int,
    5,
    'Should default to unfinished refund work'
);

-- Should expose unresolved checkout work for a canceled event
select is(
    (
        select refund->>'status'
        from jsonb_array_elements(
            list_group_refunds(
                :'groupID'::uuid,
                '{"limit": 50, "offset": 0}'::jsonb
            )::jsonb->'refunds'
        ) refund
        where (refund->>'event_purchase_id')::uuid = :'waitingPurchaseID'
    ),
    'awaiting-checkout',
    'Should expose unresolved checkout work for a canceled event'
);

-- Should expose all administrator attention states
select is(
    (
        list_group_refunds(
            :'groupID'::uuid,
            '{"limit": 50, "offset": 0, "view": "attention"}'::jsonb
        )->'refunds'
    )::jsonb #> '{0,status}',
    '"retryable-failure"'::jsonb,
    'Should order and expose administrator attention states'
);

-- Should expose exhausted application-fee and credit-note work
select is(
    (
        select jsonb_agg(work->>'kind' order by work->>'kind')
        from jsonb_array_elements(
            list_group_refunds(
                :'groupID'::uuid,
                '{"limit": 50, "offset": 0, "view": "attention"}'::jsonb
            )::jsonb->'financial_recoveries'
        ) work
    ),
    '["application-fee-adjustment", "credit-note"]'::jsonb,
    'Should expose exhausted application-fee and credit-note work'
);

-- Should search ticket details and return complete financial recovery rows
select is(
    list_group_refunds(
        :'groupID'::uuid,
        '{
            "limit": 50,
            "offset": 0,
            "ts_query": "General admission",
            "view": "attention"
        }'::jsonb
    )::jsonb->'financial_recoveries',
    jsonb_build_array(
        jsonb_build_object(
            'amount_minor', 2500,
            'attempt_count', 10,
            'currency_code', 'USD',
            'email', 'retry@example.test',
            'event_name', 'Primary event',
            'failure_message', 'Credit-note request failed',
            'kind', 'credit-note',
            'operation', 'Credit note',
            'username', 'retry',
            'work_id', :'creditNoteID'::uuid,
            'name', null
        ),
        jsonb_build_object(
            'amount_minor', 25,
            'attempt_count', 10,
            'currency_code', 'USD',
            'email', 'retry@example.test',
            'event_name', 'Primary event',
            'failure_message', 'Application-fee request failed',
            'kind', 'application-fee-adjustment',
            'operation', 'Tax fee correction',
            'username', 'retry',
            'work_id', :'feeAdjustmentID'::uuid,
            'name', null
        )
    ),
    'Should search ticket details and return complete financial recovery rows'
);

-- Should hide unresolved financial work from the completed view
select is(
    jsonb_array_length(
        list_group_refunds(
            :'groupID'::uuid,
            '{"limit": 50, "offset": 0, "view": "completed"}'::jsonb
        )::jsonb->'financial_recoveries'
    ),
    0,
    'Should hide unresolved financial work from the completed view'
);

-- Should include review and retry work in the attention view
select is(
    (
        list_group_refunds(
            :'groupID'::uuid,
            '{"limit": 50, "offset": 0, "view": "attention"}'::jsonb
        )->>'total'
    )::int,
    4,
    'Should include review and retry work in the attention view'
);

-- Should include refunded and rejected history in the completed view
select is(
    (
        list_group_refunds(
            :'groupID'::uuid,
            '{"limit": 50, "offset": 0, "view": "completed"}'::jsonb
        )->>'total'
    )::int,
    2,
    'Should include refunded and rejected history in the completed view'
);

-- Should include every refund workflow in the all view
select is(
    (
        list_group_refunds(
            :'groupID'::uuid,
            '{"limit": 50, "offset": 0, "view": "all"}'::jsonb
        )->>'total'
    )::int,
    7,
    'Should include every refund workflow in the all view'
);

-- Should filter refund history by event, including deleted event history
select is(
    (
        list_group_refunds(
            :'groupID'::uuid,
            jsonb_build_object(
                'event_id', :'event2ID'::uuid,
                'limit', 50,
                'offset', 0,
                'view', 'all'
            )
        )->'refunds'->0->>'event_purchase_id'
    )::uuid,
    :'refundedPurchaseID'::uuid,
    'Should filter refund history by event, including deleted event history'
);

-- Should search attendee, event, and ticket details
select is(
    (
        list_group_refunds(
            :'groupID'::uuid,
            '{
                "limit": 50,
                "offset": 0,
                "ts_query": "requester@example.test",
                "view": "all"
            }'::jsonb
        )->'refunds'->0
    )::jsonb,
    jsonb_build_object(
        'amount_minor', 2750,
        'created_at', 1704074400,
        'currency_code', 'USD',
        'email', 'requester@example.test',
        'event_id', :'eventID'::uuid,
        'event_name', 'Primary event',
        'event_purchase_id', :'needsPurchaseID'::uuid,
        'status', 'needs-review',
        'ticket_title', 'General admission',
        'updated_at', 1704078000,
        'user_id', :'needsUserID'::uuid,
        'username', 'requester',
        'attempt_count', null,
        'failure_message', null,
        'kind', 'refund-request-approval',
        'name', 'Requesting Attendee',
        'photo_url', 'https://example.test/requester.png',
        'provider_refund_id', null,
        'requested_reason', 'Unable to attend',
        'review_note', null
    ),
    'Should search attendee, event, and ticket details'
);

-- Should bound financial recovery work within the shared operational page
select results_eq(
    $$
        select
            jsonb_array_length(result->'financial_recoveries'),
            jsonb_array_length(result->'refunds'),
            (result->'financial_recoveries'->0->>'work_id')::uuid,
            (result->>'total')::int
        from (
            select list_group_refunds(
                'd4100000-0000-0000-0000-000000000006'::uuid,
                '{"limit": 1, "offset": 0, "view": "attention"}'::jsonb
            )::jsonb as result
        ) operations
    $$,
    $$ values (
        1,
        0,
        'd4100000-0000-0000-0000-000000000024'::uuid,
        4
    ) $$,
    'Should bound financial recovery work within the shared operational page'
);

-- Should paginate all operational history while retaining the filtered total
select results_eq(
    $$
        select
            (result->'refunds'->0->>'event_purchase_id')::uuid,
            (result->>'total')::int
        from (
            select list_group_refunds(
                'd4100000-0000-0000-0000-000000000006'::uuid,
                '{"limit": 1, "offset": 1, "view": "all"}'::jsonb
            )::jsonb as result
        ) refunds
    $$,
    $$ values (
        'd4100000-0000-0000-0000-000000000011'::uuid,
        7
    ) $$,
    'Should paginate all operational history while retaining the filtered total'
);

-- Should return an empty payload outside the target group
select is(
    list_group_refunds(
        :'missingGroupID'::uuid,
        '{"limit": 50, "offset": 0, "view": "all"}'::jsonb
    )::jsonb,
    '{"events": [], "financial_recoveries": [], "refunds": [], "total": 0}'::jsonb,
    'Should return an empty payload outside the target group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
