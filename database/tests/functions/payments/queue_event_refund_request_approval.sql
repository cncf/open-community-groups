-- Tests durable queueing of approved attendee refund requests.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'd4050000-0000-0000-0000-000000000001'
\set blankPurchaseID 'd4050000-0000-0000-0000-000000000002'
\set blankRequestID 'd4050000-0000-0000-0000-000000000003'
\set blankUserID 'd4050000-0000-0000-0000-000000000004'
\set communityID 'd4050000-0000-0000-0000-000000000005'
\set conflictPurchaseID 'd4050000-0000-0000-0000-000000000006'
\set conflictRefundID 'd4050000-0000-0000-0000-000000000007'
\set conflictRequestID 'd4050000-0000-0000-0000-000000000008'
\set conflictUserID 'd4050000-0000-0000-0000-000000000009'
\set eventCategoryID 'd4050000-0000-0000-0000-000000000010'
\set eventID 'd4050000-0000-0000-0000-000000000011'
\set freePurchaseID 'd4050000-0000-0000-0000-000000000012'
\set freeRequestID 'd4050000-0000-0000-0000-000000000013'
\set freeUserID 'd4050000-0000-0000-0000-000000000014'
\set groupCategoryID 'd4050000-0000-0000-0000-000000000015'
\set groupID 'd4050000-0000-0000-0000-000000000016'
\set happyPurchaseID 'd4050000-0000-0000-0000-000000000017'
\set happyRequestID 'd4050000-0000-0000-0000-000000000018'
\set happyUserID 'd4050000-0000-0000-0000-000000000019'
\set missingGroupID 'd4050000-0000-0000-0000-000000000021'
\set missingRequestPurchaseID 'd4050000-0000-0000-0000-000000000022'
\set missingRequestUserID 'd4050000-0000-0000-0000-000000000023'
\set noReferencePurchaseID 'd4050000-0000-0000-0000-000000000025'
\set noReferenceRequestID 'd4050000-0000-0000-0000-000000000026'
\set noReferenceUserID 'd4050000-0000-0000-0000-000000000027'
\set replayActorID 'd4050000-0000-0000-0000-000000000029'
\set ticketTypeID 'd4050000-0000-0000-0000-000000000028'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the refund approval fixtures
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
    'queue-refund-community'
);

-- Event category used by the refund approval event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category used by the refund approval group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Group owning the refund approval event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Users covering every approval queue validation and normalization branch
insert into "user" (auth_hash, email, user_id, username) values
    ('actor', 'actor@example.test', :'actorID', 'actor'),
    ('blank', 'blank@example.test', :'blankUserID', 'blank'),
    ('conflict', 'conflict@example.test', :'conflictUserID', 'conflict'),
    ('free', 'free@example.test', :'freeUserID', 'free'),
    ('happy', 'happy@example.test', :'happyUserID', 'happy'),
    ('missing-request', 'missing-request@example.test', :'missingRequestUserID', 'missing-request'),
    ('no-reference', 'no-reference@example.test', :'noReferenceUserID', 'no-reference'),
    ('replay-actor', 'replay-actor@example.test', :'replayActorID', 'replay-actor');

-- Event owning every approval queue purchase
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

-- Ticket type referenced by every approval queue purchase
insert into event_ticket_type (event_id, event_ticket_type_id, "order", seats_total, title)
values (:'eventID', :'ticketTypeID', 1, 100, 'General admission');

-- Purchases covering successful, blank-note, conflicting, free, missing-request, and missing-reference states
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    payment_provider_id,
    provider_payment_reference
) values
    (2500, 'USD', :'eventID', :'blankPurchaseID', :'ticketTypeID', 'refund-requested', 'General admission', :'blankUserID', 'stripe', 'pi_blank'),
    (2500, 'USD', :'eventID', :'conflictPurchaseID', :'ticketTypeID', 'refund-requested', 'General admission', :'conflictUserID', 'stripe', 'pi_conflict'),
    (0, 'USD', :'eventID', :'freePurchaseID', :'ticketTypeID', 'refund-requested', 'General admission', :'freeUserID', null, null),
    (2500, 'USD', :'eventID', :'happyPurchaseID', :'ticketTypeID', 'refund-requested', 'General admission', :'happyUserID', 'stripe', 'pi_happy'),
    (2500, 'USD', :'eventID', :'missingRequestPurchaseID', :'ticketTypeID', 'refund-requested', 'General admission', :'missingRequestUserID', 'stripe', 'pi_missing_request'),
    (2500, 'USD', :'eventID', :'noReferencePurchaseID', :'ticketTypeID', 'refund-requested', 'General admission', :'noReferenceUserID', 'stripe', null);

-- Refund requests covering successful, blank-note, conflicting, free, and missing-reference states
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status
) values
    (:'blankPurchaseID', :'blankRequestID', :'blankUserID', 'pending'),
    (:'conflictPurchaseID', :'conflictRequestID', :'conflictUserID', 'pending'),
    (:'freePurchaseID', :'freeRequestID', :'freeUserID', 'pending'),
    (:'happyPurchaseID', :'happyRequestID', :'happyUserID', 'pending'),
    (:'noReferencePurchaseID', :'noReferenceRequestID', :'noReferenceUserID', 'pending');

-- Existing cancellation refund that conflicts with attendee-request approval
insert into event_purchase_refund (
    amount_minor,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    idempotency_key,
    kind,
    payment_provider_id,
    status
) values (
    2500,
    'USD',
    :'conflictPurchaseID',
    :'conflictRefundID',
    'refund-conflict',
    'event-cancellation',
    'stripe',
    'provider-pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should normalize a blank review note while queueing durable work
select lives_ok(
    format(
        $$select queue_event_refund_request_approval(%L::uuid, %L::uuid, %L::uuid, '   ')$$,
        :'actorID', :'groupID', :'blankPurchaseID'
    ),
    'Should normalize a blank review note while queueing durable work'
);

-- Should persist null normalized notes in both lifecycle records
select results_eq(
    format($$
        select epr.review_note, err.review_note
        from event_purchase_refund epr
        join event_refund_request err using (event_refund_request_id)
        where epr.event_purchase_id = %L::uuid
    $$, :'blankPurchaseID'),
    $$ values (null::text, null::text) $$,
    'Should persist null normalized notes in both lifecycle records'
);

-- Should queue an approved paid refund request
select lives_ok(
    format(
        $$select queue_event_refund_request_approval(%L::uuid, %L::uuid, %L::uuid, '  Approved by organizer  ')$$,
        :'actorID', :'groupID', :'happyPurchaseID'
    ),
    'Should queue an approved paid refund request'
);

-- Should persist the review decision and stable worker handoff
select results_eq(
    format($$
        select
            epr.amount_minor,
            epr.currency_code,
            epr.idempotency_key,
            epr.initiated_by_user_id,
            epr.kind,
            epr.payment_provider_id,
            epr.review_note,
            epr.status,
            err.review_note,
            err.reviewed_at is not null,
            err.reviewed_by_user_id,
            err.status
        from event_purchase_refund epr
        join event_refund_request err using (event_refund_request_id)
        where epr.event_purchase_id = %L::uuid
    $$, :'happyPurchaseID'),
    format($$ values (
        2500::bigint,
        'USD'::text,
        %L::text,
        %L::uuid,
        'refund-request-approval'::text,
        'stripe'::text,
        'Approved by organizer'::text,
        'provider-pending'::text,
        'Approved by organizer'::text,
        true,
        %L::uuid,
        'approving'::text
    ) $$, 'event-purchase-refund-' || :'happyPurchaseID', :'actorID', :'actorID'),
    'Should persist the review decision and stable worker handoff'
);

-- Should accept an idempotent replay without duplicating durable work
select lives_ok(
    format(
        $$select queue_event_refund_request_approval(%L::uuid, %L::uuid, %L::uuid, 'Changed by replay')$$,
        :'replayActorID', :'groupID', :'happyPurchaseID'
    ),
    'Should accept an idempotent replay without duplicating durable work'
);

-- Should preserve the first review decision after an idempotent replay
select results_eq(
    format($$
        select
            epr.initiated_by_user_id,
            epr.review_note,
            err.reviewed_by_user_id,
            err.review_note
        from event_purchase_refund epr
        join event_refund_request err using (event_refund_request_id)
        where epr.event_purchase_id = %L::uuid
    $$, :'happyPurchaseID'),
    format(
        $$ values (%L::uuid, 'Approved by organizer'::text, %L::uuid, 'Approved by organizer'::text) $$,
        :'actorID',
        :'actorID'
    ),
    'Should preserve the first review decision after an idempotent replay'
);

-- Should keep one durable refund after an idempotent replay
select is(
    (select count(*)::int from event_purchase_refund where event_purchase_id = :'happyPurchaseID'),
    1,
    'Should keep one durable refund after an idempotent replay'
);

-- Should reject a free purchase
select throws_ok(
    format(
        $$select queue_event_refund_request_approval(%L::uuid, %L::uuid, %L::uuid, null)$$,
        :'actorID', :'groupID', :'freePurchaseID'
    ),
    'paid purchase is not ready for refund',
    'Should reject a free purchase'
);

-- Should reject a paid purchase without a provider payment reference
select throws_ok(
    format(
        $$select queue_event_refund_request_approval(%L::uuid, %L::uuid, %L::uuid, null)$$,
        :'actorID', :'groupID', :'noReferencePurchaseID'
    ),
    'paid purchase is not ready for refund',
    'Should reject a paid purchase without a provider payment reference'
);

-- Should reject a purchase without a refund request
select throws_ok(
    format(
        $$select queue_event_refund_request_approval(%L::uuid, %L::uuid, %L::uuid, null)$$,
        :'actorID', :'groupID', :'missingRequestPurchaseID'
    ),
    'refund request not found',
    'Should reject a purchase without a refund request'
);

-- Should reject a request outside the requested group
select throws_ok(
    format(
        $$select queue_event_refund_request_approval(%L::uuid, %L::uuid, %L::uuid, null)$$,
        :'actorID', :'missingGroupID', :'happyPurchaseID'
    ),
    'refund request not found',
    'Should reject a request outside the requested group'
);

-- Should reject durable work owned by a different refund kind
select throws_ok(
    format(
        $$select queue_event_refund_request_approval(%L::uuid, %L::uuid, %L::uuid, 'Approved')$$,
        :'actorID', :'groupID', :'conflictPurchaseID'
    ),
    'event purchase refund already started with different kind',
    'Should reject durable work owned by a different refund kind'
);

-- Should roll back the review decision after a conflicting durable workflow
select results_eq(
    format($$
        select review_note, reviewed_at, reviewed_by_user_id, status
        from event_refund_request
        where event_refund_request_id = %L::uuid
    $$, :'conflictRequestID'),
    $$ values (null::text, null::timestamptz, null::uuid, 'pending'::text) $$,
    'Should roll back the review decision after a conflicting durable workflow'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
