-- Tests event deletion eligibility across lifecycle and payment states.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(19);

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
\set durableTicketTypeID 'd3010000-0000-0000-0000-000000000011'
\set eventCategoryID 'd3010000-0000-0000-0000-000000000012'
\set expiredPendingEventID 'd3010000-0000-0000-0000-000000000037'
\set expiredPendingPurchaseID 'd3010000-0000-0000-0000-000000000038'
\set expiredPendingTicketTypeID 'd3010000-0000-0000-0000-000000000039'
\set finalizedEventID 'd3010000-0000-0000-0000-000000000032'
\set finalizedPurchaseID 'd3010000-0000-0000-0000-000000000033'
\set finalizedRefundID 'd3010000-0000-0000-0000-000000000034'
\set finalizedTicketTypeID 'd3010000-0000-0000-0000-000000000035'
\set groupCategoryID 'd3010000-0000-0000-0000-000000000013'
\set groupID 'd3010000-0000-0000-0000-000000000014'
\set historicalDraftEventID 'd3010000-0000-0000-0000-000000000036'
\set invitationDraftEventID 'd3010000-0000-0000-0000-000000000015'
\set missingEventID 'd3010000-0000-0000-0000-000000000016'
\set otherGroupID 'd3010000-0000-0000-0000-000000000017'
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
\set recoveredTicketTypeID 'd3010000-0000-0000-0000-000000000028'
\set userID 'd3010000-0000-0000-0000-000000000029'
\set waitlistDraftEventID 'd3010000-0000-0000-0000-000000000030'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the eligibility scenarios
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
    'delete-eligibility-community'
);

-- Event category shared by the eligibility scenarios
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group category shared by the eligibility scenarios
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Groups');

-- Groups used to verify ownership boundaries
insert into "group" (community_id, group_category_id, group_id, name, slug) values
    (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group'),
    (:'communityID', :'groupCategoryID', :'otherGroupID', 'Other Group', 'other-group');

-- Users referenced by attendance, purchase, and recovery fixtures
insert into "user" (auth_hash, email, user_id, username) values
    ('actor', 'actor@example.test', :'actorID', 'actor'),
    ('user', 'user@example.test', :'userID', 'user');

-- Events representing every lifecycle and dependency eligibility branch
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone,

    canceled,
    ends_at
) values
    ('Active', :'eventCategoryID', :'activeEventID', 'virtual', :'groupID', 'Active', true, 'active', now() + interval '1 day', 'UTC', false, now() + interval '1 day 1 hour'),
    ('Attendee draft', :'eventCategoryID', :'attendeeDraftEventID', 'virtual', :'groupID', 'Attendee Draft', false, 'attendee-draft', null, 'UTC', false, null),
    ('Audit draft', :'eventCategoryID', :'auditDraftEventID', 'virtual', :'groupID', 'Audit Draft', false, 'audit-draft', null, 'UTC', false, null),
    ('Canceled', :'eventCategoryID', :'canceledEventID', 'virtual', :'groupID', 'Canceled', true, 'canceled', now() + interval '1 day', 'UTC', true, now() + interval '1 day 1 hour'),
    ('Draft', :'eventCategoryID', :'draftEventID', 'virtual', :'groupID', 'Draft', false, 'draft', null, 'UTC', false, null),
    ('Durable refund', :'eventCategoryID', :'durableEventID', 'virtual', :'groupID', 'Durable Refund', true, 'durable-refund', now() + interval '1 day', 'UTC', true, now() + interval '1 day 1 hour'),
    ('Expired checkout', :'eventCategoryID', :'expiredPendingEventID', 'virtual', :'groupID', 'Expired Checkout', true, 'expired-checkout', now() + interval '1 day', 'UTC', true, now() + interval '1 day 1 hour'),
    ('Invitation draft', :'eventCategoryID', :'invitationDraftEventID', 'virtual', :'groupID', 'Invitation Draft', false, 'invitation-draft', null, 'UTC', false, null),
    ('Past', :'eventCategoryID', :'pastEventID', 'virtual', :'groupID', 'Past', true, 'past', now() - interval '2 hours', 'UTC', false, now() - interval '1 hour'),
    ('Pending purchase', :'eventCategoryID', :'pendingEventID', 'virtual', :'groupID', 'Pending Purchase', true, 'pending-purchase', now() + interval '1 day', 'UTC', true, now() + interval '1 day 1 hour'),
    ('Provider checkout', :'eventCategoryID', :'providerPendingEventID', 'virtual', :'groupID', 'Provider Checkout', true, 'provider-checkout', now() + interval '1 day', 'UTC', true, now() + interval '1 day 1 hour'),
    ('Purchase draft', :'eventCategoryID', :'purchaseDraftEventID', 'virtual', :'groupID', 'Purchase Draft', false, 'purchase-draft', null, 'UTC', false, null),
    ('Recovered refund', :'eventCategoryID', :'recoveredEventID', 'virtual', :'groupID', 'Recovered Refund', true, 'recovered-refund', now() + interval '1 day', 'UTC', true, now() + interval '1 day 1 hour'),
    ('Waitlist draft', :'eventCategoryID', :'waitlistDraftEventID', 'virtual', :'groupID', 'Waitlist Draft', false, 'waitlist-draft', null, 'UTC', false, null);

-- Events covering deleted, finalized-refund, and prior-publication eligibility
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone,

    canceled,
    deleted,
    deleted_at,
    ends_at,
    published_at
) values
    ('Deleted', :'eventCategoryID', :'deletedEventID', 'virtual', :'groupID', 'Deleted', false, 'deleted', null, 'UTC', false, true, current_timestamp, null, null),
    ('Finalized refund', :'eventCategoryID', :'finalizedEventID', 'virtual', :'groupID', 'Finalized Refund', true, 'finalized-refund', now() + interval '1 day', 'UTC', true, false, null, now() + interval '1 day 1 hour', current_timestamp),
    ('Historical draft', :'eventCategoryID', :'historicalDraftEventID', 'virtual', :'groupID', 'Historical Draft', false, 'historical-draft', null, 'UTC', false, false, null, null, current_timestamp);

-- Attendee that makes an unpublished draft ineligible for direct deletion
insert into event_attendee (event_id, user_id)
values (:'attendeeDraftEventID', :'userID');

-- Invitation request that makes an unpublished draft ineligible for direct deletion
insert into event_invitation_request (event_id, user_id)
values (:'invitationDraftEventID', :'userID');

-- Waitlist entry that makes an unpublished draft ineligible for direct deletion
insert into event_waitlist (event_id, user_id)
values (:'waitlistDraftEventID', :'userID');

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

-- Ticket types required by the purchase eligibility fixtures
insert into event_ticket_type (event_id, event_ticket_type_id, "order", seats_total, title) values
    (:'durableEventID', :'durableTicketTypeID', 1, 10, 'Durable'),
    (:'expiredPendingEventID', :'expiredPendingTicketTypeID', 1, 10, 'Expired'),
    (:'finalizedEventID', :'finalizedTicketTypeID', 1, 10, 'Finalized'),
    (:'pendingEventID', :'pendingTicketTypeID', 1, 10, 'Pending'),
    (:'providerPendingEventID', :'providerPendingTicketTypeID', 1, 10, 'Provider'),
    (:'purchaseDraftEventID', :'purchaseDraftTicketTypeID', 1, 10, 'Draft'),
    (:'recoveredEventID', :'recoveredTicketTypeID', 1, 10, 'Recovered');

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
    (2500, 'USD', :'durableEventID', :'durablePurchaseID', :'durableTicketTypeID', 'completed', 'Durable', :'userID', null, 'stripe', null, 'pi_durable', null),
    (2500, 'USD', :'expiredPendingEventID', :'expiredPendingPurchaseID', :'expiredPendingTicketTypeID', 'pending', 'Expired', :'userID', current_timestamp - interval '1 minute', 'stripe', null, null, null),
    (2500, 'USD', :'finalizedEventID', :'finalizedPurchaseID', :'finalizedTicketTypeID', 'refunded', 'Finalized', :'userID', null, 'stripe', null, 'pi_finalized', current_timestamp),
    (2500, 'USD', :'pendingEventID', :'pendingPurchaseID', :'pendingTicketTypeID', 'pending', 'Pending', :'userID', current_timestamp + interval '30 minutes', 'stripe', null, null, null),
    (2500, 'USD', :'providerPendingEventID', :'providerPendingPurchaseID', :'providerPendingTicketTypeID', 'pending', 'Provider', :'userID', current_timestamp - interval '1 minute', 'stripe', 'cs_pending_delete', null, null),
    (2500, 'USD', :'purchaseDraftEventID', :'purchaseDraftPurchaseID', :'purchaseDraftTicketTypeID', 'completed', 'Draft', :'userID', null, 'stripe', null, 'pi_draft', null),
    (2500, 'USD', :'recoveredEventID', :'recoveredPurchaseID', :'recoveredTicketTypeID', 'refunded', 'Recovered', :'userID', null, 'stripe', null, 'pi_recovered', current_timestamp);

-- Durable refund that blocks deletion until provider work settles
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
    :'durablePurchaseID',
    :'durableRefundID',
    'refund-durable',
    'event-cancellation',
    'stripe',
    'provider-pending'
);

-- Recovered terminal refund that no longer blocks deletion
insert into event_purchase_refund (
    amount_minor,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    finalized_at,
    idempotency_key,
    kind,
    payment_provider_id,
    provider_refund_id,
    recovery_completed_at,
    recovery_completed_by_user_id,
    recovery_note,
    recovery_reference,
    status,
    terminal_failure
) values (
    2500,
    'USD',
    :'recoveredPurchaseID',
    :'recoveredRefundID',
    current_timestamp,
    'refund-recovered',
    'event-cancellation',
    'stripe',
    're_recovered',
    current_timestamp,
    :'actorID',
    'Verified externally',
    'bank-transfer-123',
    'provider-failed',
    true
);

-- Finalized refund that no longer blocks deletion
insert into event_purchase_refund (
    amount_minor,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    finalized_at,
    idempotency_key,
    kind,
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
    'refund-finalized',
    'event-cancellation',
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

-- Should ignore a pending checkout after its hold expires
select is(
    get_event_delete_eligibility(:'groupID', :'expiredPendingEventID'),
    'allowed',
    'Should allow a canceled event after its pending checkout hold expires'
);

-- Should keep an attached provider checkout blocking after the local hold expires
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
