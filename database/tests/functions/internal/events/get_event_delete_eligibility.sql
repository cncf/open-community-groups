-- Tests event deletion eligibility across lifecycle and payment states.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(20);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeEventID 'd3010000-0000-0000-0000-000000000002'
\set actorID 'd3010000-0000-0000-0000-000000000001'
\set attendeeDraftEventID 'd3010000-0000-0000-0000-000000000003'
\set auditDraftEventID 'd3010000-0000-0000-0000-000000000004'
\set canceledEventID 'd3010000-0000-0000-0000-000000000005'
\set communityID 'd3010000-0000-0000-0000-000000000006'
\set draftEventID 'd3010000-0000-0000-0000-000000000007'
\set deletedEventID 'd3010000-0000-0000-0000-000000000031'
\set durableEventID 'd3010000-0000-0000-0000-000000000008'
\set durablePurchaseID 'd3010000-0000-0000-0000-000000000009'
\set durableRefundID 'd3010000-0000-0000-0000-000000000010'
\set durableRefundJobID 'd3010000-0000-0000-0000-000000000045'
\set durableTicketTypeID 'd3010000-0000-0000-0000-000000000011'
\set eventCategoryID 'd3010000-0000-0000-0000-000000000012'
\set expiredPendingEventID 'd3010000-0000-0000-0000-000000000037'
\set expiredPendingPurchaseID 'd3010000-0000-0000-0000-000000000038'
\set expiredPendingTicketTypeID 'd3010000-0000-0000-0000-000000000039'
\set finalizedEventID 'd3010000-0000-0000-0000-000000000032'
\set finalizedPurchaseID 'd3010000-0000-0000-0000-000000000033'
\set finalizedRefundID 'd3010000-0000-0000-0000-000000000034'
\set finalizedRefundJobID 'd3010000-0000-0000-0000-000000000046'
\set finalizedTicketTypeID 'd3010000-0000-0000-0000-000000000035'
\set groupCategoryID 'd3010000-0000-0000-0000-000000000013'
\set groupID 'd3010000-0000-0000-0000-000000000014'
\set historicalDraftEventID 'd3010000-0000-0000-0000-000000000036'
\set invitationDraftEventID 'd3010000-0000-0000-0000-000000000015'
\set missingEventID 'd3010000-0000-0000-0000-000000000016'
\set otherGroupID 'd3010000-0000-0000-0000-000000000017'
\set offerDraftEventID 'd3010000-0000-0000-0000-000000000043'
\set offerID 'd3010000-0000-0000-0000-000000000044'
\set pastEventID 'd3010000-0000-0000-0000-000000000018'
\set pendingEventID 'd3010000-0000-0000-0000-000000000019'
\set pendingPurchaseID 'd3010000-0000-0000-0000-000000000020'
\set pendingTicketTypeID 'd3010000-0000-0000-0000-000000000021'
\set providerPendingEventID 'd3010000-0000-0000-0000-000000000040'
\set providerPendingPurchaseID 'd3010000-0000-0000-0000-000000000041'
\set providerPendingTicketTypeID 'd3010000-0000-0000-0000-000000000042'
\set purchaseDraftEventID 'd3010000-0000-0000-0000-000000000022'
\set purchaseDraftPurchaseID 'd3010000-0000-0000-0000-000000000023'
\set purchaseDraftTicketTypeID 'd3010000-0000-0000-0000-000000000024'
\set recoveredEventID 'd3010000-0000-0000-0000-000000000025'
\set recoveredPurchaseID 'd3010000-0000-0000-0000-000000000026'
\set recoveredRefundID 'd3010000-0000-0000-0000-000000000027'
\set recoveredRefundJobID 'd3010000-0000-0000-0000-000000000047'
\set recoveredTicketTypeID 'd3010000-0000-0000-0000-000000000028'
\set userID 'd3010000-0000-0000-0000-000000000029'
\set waitlistDraftEventID 'd3010000-0000-0000-0000-000000000030'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');


-- Groups used to verify ownership boundaries
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Group',
    'slug', 'group'
));

-- Users referenced by attendance, purchase, and recovery fixtures
select fx_user(:'actorID', jsonb_build_object('username', 'actor-get-event-delete-eligibility'));
select fx_user(:'userID', jsonb_build_object('username', 'user-get-event-delete-eligibility'));

-- Events representing every lifecycle and dependency eligibility branch
select fx_event(:'activeEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'published', true,
    'slug', 'active',
    'starts_at', now() + interval '1 day'
));
select fx_event(:'attendeeDraftEventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'auditDraftEventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'published', true,
    'slug', 'canceled',
    'starts_at', now() + interval '1 day'
));
select fx_event(:'draftEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Draft',
    'event_kind_id', 'virtual',
    'name', 'Draft',
    'slug', 'draft'
));
select fx_event(:'durableEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 day'
));
select fx_event(:'expiredPendingEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 day'
));
select fx_event(:'invitationDraftEventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'offerDraftEventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'pastEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 hour',
    'event_kind_id', 'virtual',
    'published', true,
    'slug', 'past',
    'starts_at', now() - interval '2 hours'
));
select fx_event(:'pendingEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 day'
));
select fx_event(:'providerPendingEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 day'
));
select fx_event(:'purchaseDraftEventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'recoveredEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', now() + interval '1 day'
));
select fx_event(:'waitlistDraftEventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

-- Events covering deleted, finalized-refund, and prior-publication eligibility
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'deleted_at', current_timestamp,
    'event_kind_id', 'virtual',
    'slug', 'deleted'
));
select fx_event(:'finalizedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'published', true,
    'published_at', current_timestamp,
    'starts_at', now() + interval '1 day'
));
select fx_event(:'historicalDraftEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published_at', current_timestamp
));

-- Every event uses a free tier with stable identifiers for purchase fixtures
select fx_event_ticket_type(
    case e.event_id
        when :'durableEventID'::uuid then :'durableTicketTypeID'::uuid
        when :'expiredPendingEventID'::uuid then :'expiredPendingTicketTypeID'::uuid
        when :'finalizedEventID'::uuid then :'finalizedTicketTypeID'::uuid
        when :'pendingEventID'::uuid then :'pendingTicketTypeID'::uuid
        when :'providerPendingEventID'::uuid then :'providerPendingTicketTypeID'::uuid
        when :'purchaseDraftEventID'::uuid then :'purchaseDraftTicketTypeID'::uuid
        when :'recoveredEventID'::uuid then :'recoveredTicketTypeID'::uuid
        else gen_random_uuid()
    end,
    e.event_id,
    jsonb_build_object('seats_total', 100)
)
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Attendee that makes an unpublished draft ineligible for direct deletion
insert into event_attendee (event_id, user_id)
values (:'attendeeDraftEventID', :'userID');

-- Invitation request that makes an unpublished draft ineligible for direct deletion
insert into event_invitation_request (event_id, event_ticket_type_id, user_id)
values (
    :'invitationDraftEventID',
    (select event_ticket_type_id from event_ticket_type where event_id = :'invitationDraftEventID' limit 1),
    :'userID'
);

-- Active organizer offer that makes an unpublished draft ineligible for deletion
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    organizer_user_id,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'offerID',
    0,
    0,
    :'offerDraftEventID',
    (select event_ticket_type_id from event_ticket_type where event_id = :'offerDraftEventID' limit 1),
    current_timestamp + interval '1 hour',
    :'actorID',
    'organizer_invitation',
    'pending',
    'General Admission',
    :'userID'
);

-- Waitlist entry that makes an unpublished draft ineligible for direct deletion
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'waitlistDraftEventID',
    (select event_ticket_type_id from event_ticket_type where event_id = :'waitlistDraftEventID' limit 1),
    :'userID'
);

-- Publication audit history that makes an unpublished draft ineligible for direct deletion
insert into audit_log (
    action,
    actor_user_id,
    community_id,
    event_id,
    group_id,
    resource_id,
    resource_type
) values (
    'event_published',
    :'actorID',
    :'communityID',
    :'auditDraftEventID',
    :'groupID',
    :'auditDraftEventID',
    'event'
);

-- Purchases representing pending, historical, unresolved, and recovered work
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_payment_reference,
    refunded_at
) values
    (0, 'USD', :'durableEventID', :'durablePurchaseID', :'durableTicketTypeID', 'completed', 'Durable', :'userID', null, 'stripe', null, 'pi_durable', null),
    (0, 'USD', :'expiredPendingEventID', :'expiredPendingPurchaseID', :'expiredPendingTicketTypeID', 'pending', 'Expired', :'userID', current_timestamp - interval '1 minute', 'stripe', null, null, null),
    (0, 'USD', :'finalizedEventID', :'finalizedPurchaseID', :'finalizedTicketTypeID', 'refunded', 'Finalized', :'userID', null, 'stripe', null, 'pi_finalized', current_timestamp),
    (0, 'USD', :'pendingEventID', :'pendingPurchaseID', :'pendingTicketTypeID', 'pending', 'Pending', :'userID', current_timestamp + interval '30 minutes', 'stripe', null, null, null),
    (0, 'USD', :'providerPendingEventID', :'providerPendingPurchaseID', :'providerPendingTicketTypeID', 'pending', 'Provider', :'userID', current_timestamp - interval '1 minute', 'stripe', 'cs_pending_delete', null, null),
    (0, 'USD', :'purchaseDraftEventID', :'purchaseDraftPurchaseID', :'purchaseDraftTicketTypeID', 'completed', 'Draft', :'userID', null, 'stripe', null, 'pi_draft', null),
    (0, 'USD', :'recoveredEventID', :'recoveredPurchaseID', :'recoveredTicketTypeID', 'refunded', 'Recovered', :'userID', null, 'stripe', null, 'pi_recovered', current_timestamp);

-- Durable refund job that blocks deletion until provider work settles
insert into payment_job (
    event_purchase_id,
    idempotency_key,
    kind,
    payment_job_id,
    payment_provider_id,
    status
) values (
    :'durablePurchaseID',
    'delete-eligibility-durable-refund-d301',
    'event-purchase-refund',
    :'durableRefundJobID',
    'stripe',
    'pending'
);

-- Durable refund that blocks deletion until provider work settles
insert into event_purchase_refund (
    amount_minor,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    kind,
    payment_job_id,
    payment_provider_id,
    status
) values (
    2500,
    'USD',
    :'durablePurchaseID',
    :'durableRefundID',
    'event-cancellation',
    :'durableRefundJobID',
    'stripe',
    'provider-pending'
);

-- Recovered terminal refund job that no longer blocks deletion
insert into payment_job (
    completed_at,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_job_id,
    payment_provider_id,
    recovery_completed_at,
    recovery_completed_by_user_id,
    recovery_note,
    recovery_reference,
    status
) values (
    current_timestamp,
    :'recoveredPurchaseID',
    'delete-eligibility-recovered-refund-d301',
    'event-purchase-refund',
    :'recoveredRefundJobID',
    'stripe',
    current_timestamp,
    :'actorID',
    'Verified externally',
    'bank-transfer-123',
    'completed'
);

-- Recovered terminal refund that no longer blocks deletion
insert into event_purchase_refund (
    amount_minor,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    finalized_at,
    kind,
    payment_job_id,
    payment_provider_id,
    provider_refund_id,
    status,
    terminal_failure
) values (
    2500,
    'USD',
    :'recoveredPurchaseID',
    :'recoveredRefundID',
    current_timestamp,
    'event-cancellation',
    :'recoveredRefundJobID',
    'stripe',
    're_recovered',
    'provider-failed',
    true
);

-- Finalized refund job that no longer blocks deletion
insert into payment_job (
    completed_at,
    event_purchase_id,
    idempotency_key,
    kind,
    payment_job_id,
    payment_provider_id,
    status
) values (
    current_timestamp,
    :'finalizedPurchaseID',
    'delete-eligibility-finalized-refund-d301',
    'event-purchase-refund',
    :'finalizedRefundJobID',
    'stripe',
    'completed'
);

-- Finalized refund that no longer blocks deletion
insert into event_purchase_refund (
    amount_minor,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    finalized_at,
    kind,
    payment_job_id,
    payment_provider_id,
    provider_refund_id,
    provider_refunded_at,
    status
) values (
    2500,
    'USD',
    :'finalizedPurchaseID',
    :'finalizedRefundID',
    current_timestamp,
    'event-cancellation',
    :'finalizedRefundJobID',
    'stripe',
    're_finalized',
    current_timestamp,
    'finalized'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow a canceled event
select is(
    get_event_delete_eligibility(:'groupID', :'canceledEventID'),
    'allowed',
    'Should allow a canceled event'
);

-- Should allow a completed past event
select is(
    get_event_delete_eligibility(:'groupID', :'pastEventID'),
    'allowed',
    'Should allow a completed past event'
);

-- Should allow a finalized durable refund
select is(
    get_event_delete_eligibility(:'groupID', :'finalizedEventID'),
    'allowed',
    'Should allow a finalized durable refund'
);

-- Should allow a recovered terminal refund
select is(
    get_event_delete_eligibility(:'groupID', :'recoveredEventID'),
    'allowed',
    'Should allow a recovered terminal refund'
);

-- Should allow an unused never-published draft
select is(
    get_event_delete_eligibility(:'groupID', :'draftEventID'),
    'allowed',
    'Should allow an unused never-published draft'
);

-- Should require cancellation for a draft with an attendee
select is(
    get_event_delete_eligibility(:'groupID', :'attendeeDraftEventID'),
    'cancel-first',
    'Should require cancellation for a draft with an attendee'
);

-- Should require cancellation for a draft with an invitation request
select is(
    get_event_delete_eligibility(:'groupID', :'invitationDraftEventID'),
    'cancel-first',
    'Should require cancellation for a draft with an invitation request'
);

-- Should require cancellation for a draft with an active admission offer
select is(
    get_event_delete_eligibility(:'groupID', :'offerDraftEventID'),
    'cancel-first',
    'Should require cancellation for a draft with an active admission offer'
);

-- Should require cancellation for an unpublished event with publication history
select is(
    get_event_delete_eligibility(:'groupID', :'historicalDraftEventID'),
    'cancel-first',
    'Should require cancellation for an unpublished event with publication history'
);

-- Should require cancellation for a draft with a publication audit
select is(
    get_event_delete_eligibility(:'groupID', :'auditDraftEventID'),
    'cancel-first',
    'Should require cancellation for a draft with a publication audit'
);

-- Should require cancellation for a draft with a purchase
select is(
    get_event_delete_eligibility(:'groupID', :'purchaseDraftEventID'),
    'cancel-first',
    'Should require cancellation for a draft with a purchase'
);

-- Should require cancellation for a draft with a waitlist entry
select is(
    get_event_delete_eligibility(:'groupID', :'waitlistDraftEventID'),
    'cancel-first',
    'Should require cancellation for a draft with a waitlist entry'
);

-- Should require cancellation for an active published event
select is(
    get_event_delete_eligibility(:'groupID', :'activeEventID'),
    'cancel-first',
    'Should require cancellation for an active published event'
);

-- Should report an unresolved durable refund
select is(
    get_event_delete_eligibility(:'groupID', :'durableEventID'),
    'refunds-pending',
    'Should report an unresolved durable refund'
);

-- Should report a pending purchase
select is(
    get_event_delete_eligibility(:'groupID', :'pendingEventID'),
    'refunds-pending',
    'Should report a pending purchase'
);

-- Should allow a canceled event after its pending checkout hold expires
select is(
    get_event_delete_eligibility(:'groupID', :'expiredPendingEventID'),
    'allowed',
    'Should allow a canceled event after its pending checkout hold expires'
);

-- Should block deletion while an attached provider checkout can still complete
select is(
    get_event_delete_eligibility(:'groupID', :'providerPendingEventID'),
    'refunds-pending',
    'Should block deletion while an attached provider checkout can still complete'
);

-- Should return no eligibility for an event outside the group
select is(
    get_event_delete_eligibility(:'otherGroupID', :'activeEventID'),
    null::text,
    'Should return no eligibility for an event outside the group'
);

-- Should return no eligibility for a deleted event
select is(
    get_event_delete_eligibility(:'groupID', :'deletedEventID'),
    null::text,
    'Should return no eligibility for a deleted event'
);

-- Should return no eligibility for a missing event
select is(
    get_event_delete_eligibility(:'groupID', :'missingEventID'),
    null::text,
    'Should return no eligibility for a missing event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
