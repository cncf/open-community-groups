-- Tests local finalization after a provider refund succeeds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(21);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '79020000-0000-0000-0000-000000000001'
\set communityID '79020000-0000-0000-0000-000000000002'
\set discountCodeID '79020000-0000-0000-0000-000000000003'
\set eventCategoryID '79020000-0000-0000-0000-000000000004'
\set eventID '79020000-0000-0000-0000-000000000005'
\set groupCategoryID '79020000-0000-0000-0000-000000000006'
\set groupID '79020000-0000-0000-0000-000000000007'
\set happyClaimID '79020000-0000-0000-0000-000000000008'
\set happyJobID '79020000-0000-0000-0000-000000000041'
\set happyPurchaseID '79020000-0000-0000-0000-000000000009'
\set happyRefundID '79020000-0000-0000-0000-000000000010'
\set happyRequestID '79020000-0000-0000-0000-000000000011'
\set happyUserID '79020000-0000-0000-0000-000000000012'
\set incompleteClaimID '79020000-0000-0000-0000-000000000013'
\set incompleteJobID '79020000-0000-0000-0000-000000000042'
\set incompletePurchaseID '79020000-0000-0000-0000-000000000014'
\set incompleteRefundID '79020000-0000-0000-0000-000000000015'
\set incompleteUserID '79020000-0000-0000-0000-000000000016'
\set missingRefundID '79020000-0000-0000-0000-000000000017'
\set questionsClaimID '79020000-0000-0000-0000-000000000018'
\set questionsJobID '79020000-0000-0000-0000-000000000043'
\set questionsPurchaseID '79020000-0000-0000-0000-000000000019'
\set questionsRefundID '79020000-0000-0000-0000-000000000020'
\set questionsUserID '79020000-0000-0000-0000-000000000021'
\set rejectedClaimID '79020000-0000-0000-0000-000000000028'
\set rejectedJobID '79020000-0000-0000-0000-000000000044'
\set rejectedPurchaseID '79020000-0000-0000-0000-000000000029'
\set rejectedRefundID '79020000-0000-0000-0000-000000000030'
\set rejectedRequestID '79020000-0000-0000-0000-000000000031'
\set rejectedUserID '79020000-0000-0000-0000-000000000032'
\set reopenedClaimID '79020000-0000-0000-0000-000000000047'
\set reopenedJobID '79020000-0000-0000-0000-000000000048'
\set reopenedPurchaseID '79020000-0000-0000-0000-000000000049'
\set reopenedRefundID '79020000-0000-0000-0000-000000000050'
\set reopenedUserID '79020000-0000-0000-0000-000000000051'
\set replacementClaimID '79020000-0000-0000-0000-000000000035'
\set replacementJobID '79020000-0000-0000-0000-000000000045'
\set replacementOfferID '79020000-0000-0000-0000-000000000040'
\set replacementPurchaseID '79020000-0000-0000-0000-000000000036'
\set replacementRefundedPurchaseID '79020000-0000-0000-0000-000000000037'
\set replacementRefundID '79020000-0000-0000-0000-000000000038'
\set replacementUserID '79020000-0000-0000-0000-000000000039'
\set staleClaimID '79020000-0000-0000-0000-000000000022'
\set staleJobID '79020000-0000-0000-0000-000000000046'
\set stalePurchaseID '79020000-0000-0000-0000-000000000023'
\set staleRefundID '79020000-0000-0000-0000-000000000024'
\set staleUserID '79020000-0000-0000-0000-000000000025'
\set ticketTypeID '79020000-0000-0000-0000-000000000026'
\set ticketPriceWindowID '79020000-0000-0000-0000-000000000033'
\set waitlistUserID '79020000-0000-0000-0000-000000000034'
\set wrongClaimID '79020000-0000-0000-0000-000000000027'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'actorID');
select fx_user(:'incompleteUserID');
select fx_user(:'staleUserID');

-- Group owning the finalization event
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', '{"provider": "stripe", "recipient_id": "acct_finalize", "seller_display_name": "Finalize Refund Fiscal Sponsor"}'::jsonb));

-- Users covering attendee-request, automatic, rejected, reopened and waitlist claims
select fx_user(:'happyUserID', jsonb_build_object('username', 'happy'));
select fx_user(:'questionsUserID', jsonb_build_object('username', 'questions'));
select fx_user(:'rejectedUserID', jsonb_build_object('username', 'rejected-finalize-event-purchase-refund'));
select fx_user(:'reopenedUserID', jsonb_build_object('username', 'reopened-finalize-event-purchase-refund'));
select fx_user(:'replacementUserID', jsonb_build_object('username', 'replacement'));
select fx_user(:'waitlistUserID', jsonb_build_object('username', 'waitlist-finalize-event-purchase-refund'));

-- Event owning every finalization purchase
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'slug', 'event',
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Ticket type referenced by every finalization purchase
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 6,
    'title', 'General admission'
));

-- Current paid price used when reconciliation promotes the queue
select fx_event_ticket_price_window(:'ticketPriceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 2500));

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

-- Completed offer shared by a late payment and its replacement.
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'replacementOfferID',
    2500,
    'USD',
    0,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'completed',
    'General admission',
    :'replacementUserID'
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
    provider_payment_reference,

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
    fixtures.amount_minor,
    fixtures.currency_code,
    fixtures.event_id::uuid,
    fixtures.event_purchase_id::uuid,
    fixtures.event_ticket_type_id::uuid,
    fixtures.status,
    fixtures.ticket_title,
    fixtures.user_id::uuid,
    fixtures.discount_amount_minor,
    fixtures.discount_code,
    fixtures.event_discount_code_id::uuid,
    fixtures.payment_provider_id,
    fixtures.provider_payment_reference,

    'direct-charge',
    'acct_refunds',
    0,
    'ch_' || fixtures.event_purchase_id,
    'cs_' || fixtures.event_purchase_id,
    'acct_refunds',
    fixtures.amount_minor,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    fixtures.amount_minor,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
from (values
    (2500, 'USD', :'eventID', :'happyPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'happyUserID', 500, 'SAVE5', :'discountCodeID', 'stripe', 'pi_happy'),
    (2500, 'USD', :'eventID', :'incompletePurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'incompleteUserID', 0, null, null, 'stripe', 'pi_incomplete'),
    (2000, 'USD', :'eventID', :'questionsPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'questionsUserID', 500, 'SAVE5', :'discountCodeID', 'stripe', 'pi_questions'),
    (2500, 'USD', :'eventID', :'rejectedPurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'rejectedUserID', 0, null, null, 'stripe', 'pi_rejected'),
    (2500, 'USD', :'eventID', :'stalePurchaseID', :'ticketTypeID', 'refund-pending', 'General admission', :'staleUserID', 0, null, null, 'stripe', 'pi_stale')
) as fixtures (
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
);

-- Replacement and late-refund purchases linked to the same completed offer.
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
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
    fixtures.admission_offer_id::uuid,
    fixtures.amount_minor,
    fixtures.currency_code,
    fixtures.discount_amount_minor,
    fixtures.event_id::uuid,
    fixtures.event_purchase_id::uuid,
    fixtures.event_ticket_type_id::uuid,
    fixtures.payment_provider_id,
    fixtures.provider_payment_reference,
    fixtures.status,
    fixtures.ticket_title,
    fixtures.user_id::uuid,

    'direct-charge',
    'acct_refunds',
    0,
    'ch_' || fixtures.event_purchase_id,
    'cs_' || fixtures.event_purchase_id,
    'acct_refunds',
    fixtures.amount_minor,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    fixtures.amount_minor,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
from (values
    (
        :'replacementOfferID', 2500, 'USD', 0, :'eventID', :'replacementPurchaseID',
        :'ticketTypeID', 'stripe', 'pi_replacement', 'completed', 'General admission',
        :'replacementUserID'
    ),
    (
        :'replacementOfferID', 2500, 'USD', 0, :'eventID', :'replacementRefundedPurchaseID',
        :'ticketTypeID', 'stripe', 'pi_replaced', 'refund-pending', 'General admission',
        :'replacementUserID'
    )
) as fixtures (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_payment_reference,
    status,
    ticket_title,
    user_id
);

-- Already refunded purchase whose finalized refund job was re-claimed by a worker
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
    provider_payment_reference,
    refunded_at,

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
) values (
    2500,
    'USD',
    :'eventID',
    :'reopenedPurchaseID',
    :'ticketTypeID',
    'refunded',
    'General admission',
    :'reopenedUserID',

    'stripe',
    'pi_reopened_finalize_event_purchase_refund',
    '2024-01-01 00:00:00+00',

    'direct-charge',
    'acct_refunds',
    0,
    'ch_' || :'reopenedPurchaseID',
    'cs_' || :'reopenedPurchaseID',
    'acct_refunds',
    2500,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    2500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
);

-- Attendee rows removed from active capacity only after successful finalization,
-- plus a still-confirmed attendee that a finalized-refund replay must leave untouched
insert into event_attendee (checked_in, checked_in_at, event_id, status, user_id) values
    (true, current_timestamp, :'eventID', 'confirmed', :'happyUserID'),
    (false, null, :'eventID', 'confirmed', :'incompleteUserID'),
    (false, null, :'eventID', 'registration-questions-pending', :'questionsUserID'),
    (false, null, :'eventID', 'confirmed', :'reopenedUserID'),
    (true, current_timestamp, :'eventID', 'confirmed', :'replacementUserID'),
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

-- Processing payment jobs covering complete, incomplete, automatic, rejected, and stale claims
insert into payment_job (
    payment_job_id, attempt_count, event_purchase_id, idempotency_key,
    kind, payment_provider_id, status,

    claim_id, claimed_at
) values
    (:'happyJobID', 1, :'happyPurchaseID', 'refund-happy-finalize-event-purchase-refund', 'event-purchase-refund', 'stripe', 'processing', :'happyClaimID', current_timestamp),
    (:'incompleteJobID', 1, :'incompletePurchaseID', 'refund-incomplete-finalize-event-purchase-refund', 'event-purchase-refund', 'stripe', 'processing', :'incompleteClaimID', current_timestamp),
    (:'questionsJobID', 1, :'questionsPurchaseID', 'refund-questions-finalize-event-purchase-refund', 'event-purchase-refund', 'stripe', 'processing', :'questionsClaimID', current_timestamp),
    (:'rejectedJobID', 1, :'rejectedPurchaseID', 'refund-rejected-finalize-event-purchase-refund', 'event-purchase-refund', 'stripe', 'processing', :'rejectedClaimID', current_timestamp),
    (:'replacementJobID', 1, :'replacementRefundedPurchaseID', 'refund-replaced-finalize-event-purchase-refund', 'event-purchase-refund', 'stripe', 'processing', :'replacementClaimID', current_timestamp),
    (:'staleJobID', 1, :'stalePurchaseID', 'refund-stale-finalize-event-purchase-refund', 'event-purchase-refund', 'stripe', 'processing', :'staleClaimID', current_timestamp);

-- Re-claimed processing job left open after a stale sweep although its refund is already finalized
insert into payment_job (
    payment_job_id, attempt_count, event_purchase_id, idempotency_key,
    kind, next_attempt_at, payment_provider_id, status,

    claim_id, claimed_at, failure_message
) values (
    :'reopenedJobID', 3, :'reopenedPurchaseID', 'refund-reopened-finalize-event-purchase-refund',
    'event-purchase-refund', '2024-01-01 00:00:00+00', 'stripe', 'processing',

    :'reopenedClaimID', current_timestamp, 'payment job claim expired'
);

-- Claimed refund rows covering complete, incomplete, automatic, rejected, and stale claims
insert into event_purchase_refund (
    amount_minor,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    initiated_by_user_id,
    kind,
    payment_job_id,
    payment_provider_id,
    review_note,
    status,

    event_refund_request_id,
    provider_refund_id,
    provider_refunded_at
) values
    (2500, 'USD', :'happyPurchaseID', :'happyRefundID', :'actorID', 'refund-request-approval', :'happyJobID', 'stripe', 'Approved by organizer', 'provider-succeeded', :'happyRequestID', 're_happy', current_timestamp),
    (2500, 'USD', :'incompletePurchaseID', :'incompleteRefundID', :'actorID', 'event-cancellation', :'incompleteJobID', 'stripe', null, 'provider-pending', null, null, null),
    (2000, 'USD', :'questionsPurchaseID', :'questionsRefundID', null, 'automatic-unfulfillable-checkout', :'questionsJobID', 'stripe', null, 'provider-succeeded', null, 're_questions', current_timestamp),
    (2500, 'USD', :'rejectedPurchaseID', :'rejectedRefundID', :'actorID', 'event-cancellation', :'rejectedJobID', 'stripe', null, 'provider-succeeded', :'rejectedRequestID', 're_rejected', current_timestamp),
    (2500, 'USD', :'replacementRefundedPurchaseID', :'replacementRefundID', null, 'automatic-unfulfillable-checkout', :'replacementJobID', 'stripe', null, 'provider-succeeded', null, 're_replaced', current_timestamp),
    (2500, 'USD', :'stalePurchaseID', :'staleRefundID', :'actorID', 'event-cancellation', :'staleJobID', 'stripe', null, 'provider-succeeded', null, 're_stale_finalize_event_purchase_refund', current_timestamp);

-- Finalized refund whose job was re-opened and re-claimed without un-finalizing it
insert into event_purchase_refund (
    amount_minor,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    initiated_by_user_id,
    kind,
    payment_job_id,
    payment_provider_id,
    status,

    finalized_at,
    provider_refund_id,
    provider_refunded_at
) values (
    2500,
    'USD',
    :'reopenedPurchaseID',
    :'reopenedRefundID',
    :'actorID',
    'event-cancellation',
    :'reopenedJobID',
    'stripe',
    'finalized',

    '2024-01-01 00:00:00+00',
    're_reopened_finalize_event_purchase_refund',
    '2024-01-01 00:00:00+00'
);

-- FIFO waitlist entry offered the seat released by successful finalization
insert into event_waitlist (
    event_id,
    event_ticket_type_id,
    user_id
) values (
    :'eventID',
    :'ticketTypeID',
    :'waitlistUserID'
);

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

-- Should reject a worker that no longer owns the refund claim
select throws_ok(
    format(
        'select finalize_event_purchase_refund(%L::uuid, %L::uuid, %L::jsonb)',
        :'staleRefundID', :'wrongClaimID', '{}'
    ),
    'payment job claim is stale',
    'Should reject a worker that no longer owns the refund claim'
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
            pj.status,
            count(n.notification_id)::int
        from event_purchase ep
        join event_attendee ea
            on ea.event_id = ep.event_id
            and ea.user_id = ep.user_id
        join event_purchase_refund epr using (event_purchase_id)
        join payment_job pj using (payment_job_id)
        left join notification n on n.user_id = ep.user_id
        where ep.event_purchase_id = %L::uuid
        group by ep.status, ea.status, epr.status, pj.status
    $$, :'happyPurchaseID'),
    $$ values (
        'refund-pending'::text,
        'confirmed'::text,
        'provider-succeeded'::text,
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
                jsonb_build_object('scenario', 'happy'),
                'stripe'
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
            epr.finalized_at is not null,
            epr.status,
            pj.claim_id,
            pj.claimed_at,
            pj.status,
            pj.completed_at is not null
        from event_purchase ep
        join event_attendee ea
            on ea.event_id = ep.event_id
            and ea.user_id = ep.user_id
        join event_discount_code edc using (event_discount_code_id)
        join event_purchase_refund epr using (event_purchase_id)
        join event_refund_request err using (event_purchase_id)
        join payment_job pj using (payment_job_id)
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
        true,
        'finalized'::text,
        null::uuid,
        null::timestamptz,
        'completed'::text,
        true
    ) $$, :'actorID', :'actorID'),
    'Should finalize purchase, attendance, review, discount, and claim state atomically'
);

-- Should reconcile the ticket queue after refund capacity is released
select results_eq(
    format(
        $$
            select
                ao.status,
                ao.user_id,
                count(ew.user_id)
            from admission_offer ao
            left join event_waitlist ew
                on ew.event_id = ao.event_id
                and ew.event_ticket_type_id = ao.event_ticket_type_id
            where ao.event_id = %L::uuid
            and ao.source = 'waitlist'
            group by ao.status, ao.user_id
        $$,
        :'eventID'
    ),
    format(
        $$ values ('pending'::text, %L::uuid, 0::bigint) $$,
        :'waitlistUserID'
    ),
    'Should reconcile the ticket queue after refund capacity is released'
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

-- Should reject a stale claim replaying a finalized refund with an open job
select throws_ok(
    format(
        'select finalize_event_purchase_refund(%L::uuid, %L::uuid, %L::jsonb)',
        :'reopenedRefundID', :'wrongClaimID', '{}'
    ),
    'payment job claim is stale',
    'Should reject a stale claim replaying a finalized refund with an open job'
);

-- Should complete the open job when replaying an already finalized refund
select lives_ok(
    format(
        $$
            select finalize_event_purchase_refund(
                %L::uuid,
                %L::uuid,
                jsonb_build_object('scenario', 'reopened')
            )
        $$,
        :'reopenedRefundID',
        :'reopenedClaimID'
    ),
    'Should complete the open job when replaying an already finalized refund'
);

-- Should close the job without repeating finalization side effects
select results_eq(
    format($$
        select
            pj.attempt_count,
            pj.claim_id,
            pj.claimed_at,
            pj.completed_at is not null,
            pj.failure_message,
            pj.idempotency_key,
            pj.next_attempt_at,
            pj.status,
            epr.finalized_at,
            epr.provider_refunded_at,
            epr.status,
            ep.refunded_at,
            ep.status,
            ea.attendance_canceled_at,
            ea.status,
            (
                select count(*)::int
                from audit_log al
                where al.action = 'event_refunded'
                and al.details->>'event_purchase_id' = ep.event_purchase_id::text
            ),
            (
                select count(*)::int
                from notification n
                where n.kind = 'event-refund-approved'
                and n.user_id = ep.user_id
            )
        from payment_job pj
        join event_purchase_refund epr
            on epr.payment_job_id = pj.payment_job_id
        join event_purchase ep
            on ep.event_purchase_id = epr.event_purchase_id
        join event_attendee ea
            on ea.event_id = ep.event_id
            and ea.user_id = ep.user_id
        where pj.payment_job_id = %L::uuid
    $$, :'reopenedJobID'),
    $$ values (
        3,
        null::uuid,
        null::timestamptz,
        true,
        null::text,
        'refund-reopened-finalize-event-purchase-refund'::text,
        '2024-01-01 00:00:00+00'::timestamptz,
        'completed'::text,
        '2024-01-01 00:00:00+00'::timestamptz,
        '2024-01-01 00:00:00+00'::timestamptz,
        'finalized'::text,
        '2024-01-01 00:00:00+00'::timestamptz,
        'refunded'::text,
        null::timestamptz,
        'confirmed'::text,
        0,
        0
    ) $$,
    'Should close the job without repeating finalization side effects'
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

-- Should finalize an automatic refund after a replacement purchase completes
select lives_ok(
    format(
        $$
            select finalize_event_purchase_refund(
                %L::uuid,
                %L::uuid,
                jsonb_build_object('scenario', 'replacement')
            )
        $$,
        :'replacementRefundID',
        :'replacementClaimID'
    ),
    'Should finalize an automatic refund after a replacement purchase completes'
);

-- Should preserve attendance owned by the completed replacement purchase
select results_eq(
    format($$
        select
            refunded_purchase.status,
            replacement_purchase.status,
            ea.attendance_canceled_at,
            ea.checked_in,
            ea.status,
            epr.status
        from event_purchase refunded_purchase
        join event_purchase replacement_purchase
            on replacement_purchase.event_purchase_id = %L::uuid
        join event_attendee ea
            on ea.event_id = refunded_purchase.event_id
            and ea.user_id = refunded_purchase.user_id
        join event_purchase_refund epr
            on epr.event_purchase_id = refunded_purchase.event_purchase_id
        where refunded_purchase.event_purchase_id = %L::uuid
    $$, :'replacementPurchaseID', :'replacementRefundedPurchaseID'),
    $$ values (
        'refunded'::text,
        'completed'::text,
        null::timestamptz,
        true,
        'confirmed'::text,
        'finalized'::text
    ) $$,
    'Should preserve attendance owned by the completed replacement purchase'
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
