-- Tests requesting event purchase refunds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79470000-0000-0000-0000-000000000001'
\set communityManagerID '79470000-0000-0000-0000-000000000002'
\set communityNoReviewID '79470000-0000-0000-0000-000000000003'
\set communityViewerID '79470000-0000-0000-0000-000000000004'
\set eventCanceledID '79470000-0000-0000-0000-000000000005'
\set eventCanceledTicketTypeID '79470000-0000-0000-0000-000000000006'
\set eventCategoryID '79470000-0000-0000-0000-000000000007'
\set eventCategoryNoReviewID '79470000-0000-0000-0000-000000000008'
\set eventID '79470000-0000-0000-0000-000000000009'
\set eventNoTeamID '79470000-0000-0000-0000-000000000010'
\set eventNoTeamTicketTypeID '79470000-0000-0000-0000-000000000011'
\set eventStartedID '79470000-0000-0000-0000-000000000012'
\set eventStartedTicketTypeID '79470000-0000-0000-0000-000000000013'
\set eventTicketTypeID '79470000-0000-0000-0000-000000000014'
\set eventUnpublishedID '79470000-0000-0000-0000-000000000015'
\set eventUnpublishedTicketTypeID '79470000-0000-0000-0000-000000000016'
\set groupCategoryID '79470000-0000-0000-0000-000000000017'
\set groupCategoryNoReviewID '79470000-0000-0000-0000-000000000018'
\set groupID '79470000-0000-0000-0000-000000000019'
\set groupNoTeamID '79470000-0000-0000-0000-000000000020'
\set priceWindowCanceledID '79470000-0000-0000-0000-000000000021'
\set priceWindowID '79470000-0000-0000-0000-000000000022'
\set priceWindowNoTeamID '79470000-0000-0000-0000-000000000023'
\set priceWindowStartedID '79470000-0000-0000-0000-000000000024'
\set priceWindowUnpublishedID '79470000-0000-0000-0000-000000000025'
\set purchaseCanceledID '79470000-0000-0000-0000-000000000026'
\set purchaseExpiredID '79470000-0000-0000-0000-000000000027'
\set purchaseID '79470000-0000-0000-0000-000000000028'
\set purchaseNoTeamID '79470000-0000-0000-0000-000000000029'
\set purchaseStartedID '79470000-0000-0000-0000-000000000030'
\set purchaseUnpublishedID '79470000-0000-0000-0000-000000000031'
\set refundRequestID '79470000-0000-0000-0000-000000000032'
\set requesterID '79470000-0000-0000-0000-000000000033'
\set teamUser1ID '79470000-0000-0000-0000-000000000034'
\set teamUser2ID '79470000-0000-0000-0000-000000000035'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, categories, users and groups
select fx_community(:'communityID');
select fx_community(:'communityNoReviewID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group_category(:'groupCategoryNoReviewID', :'communityNoReviewID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_event_category(:'eventCategoryNoReviewID', :'communityNoReviewID');
select fx_user(:'communityViewerID');
select fx_user(:'requesterID');
select fx_user(:'teamUser2ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupNoTeamID', :'communityNoReviewID', :'groupCategoryNoReviewID');

-- Notification users with asserted usernames
select fx_user(:'communityManagerID', jsonb_build_object('username', 'community-manager'));
select fx_user(:'teamUser1ID', jsonb_build_object('username', 'organizer-1'));

-- Group team
insert into group_team (group_id, user_id, accepted, role) values
    (:'groupID', :'teamUser1ID', true, 'admin'),
    (:'groupID', :'teamUser2ID', true, 'viewer');

-- Community team
insert into community_team (accepted, community_id, role, user_id) values
    (true, :'communityID', 'groups-manager', :'communityManagerID'),
    (true, :'communityID', 'viewer', :'communityViewerID');

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days'
));
select fx_event(:'eventStartedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', now(),
    'starts_at', now() - interval '1 hour'
));
select fx_event(:'eventCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days'
));
select fx_event(:'eventNoTeamID', :'groupNoTeamID', :'eventCategoryNoReviewID', jsonb_build_object(
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days'
));
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days'
));

-- Ticket type and price window
select fx_event_ticket_type(:'eventCanceledTicketTypeID', :'eventCanceledID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'eventNoTeamTicketTypeID', :'eventNoTeamID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'eventStartedTicketTypeID', :'eventStartedID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'eventUnpublishedTicketTypeID', :'eventUnpublishedID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Price window that supplies the refundable purchase amount
select fx_event_ticket_price_window(:'priceWindowCanceledID', :'eventCanceledTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'priceWindowNoTeamID', :'eventNoTeamTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'priceWindowStartedID', :'eventStartedTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'priceWindowID', :'eventTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'priceWindowUnpublishedID', :'eventUnpublishedTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

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
    fixtures.event_purchase_id::uuid,
    fixtures.amount_minor,
    fixtures.created_at,
    fixtures.currency_code,
    fixtures.event_id::uuid,
    fixtures.event_ticket_type_id::uuid,
    fixtures.status,
    fixtures.ticket_title,
    fixtures.user_id::uuid,
    coalesce(fixtures.payment_provider_id, 'stripe'),
    coalesce(fixtures.provider_payment_reference, 'pi_' || fixtures.event_purchase_id),

    'direct-charge',
    'acct_refunds',
    case when fixtures.status = 'completed' then 0 end,
    case when fixtures.status = 'completed' then 'ch_' || fixtures.event_purchase_id end,
    case when fixtures.status = 'completed' then 'cs_' || fixtures.event_purchase_id end,
    'acct_refunds',
    case when fixtures.status = 'completed' then fixtures.amount_minor end,
    '{"connected_account_id":"acct_refunds","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    case when fixtures.status = 'completed' then fixtures.amount_minor end,
    case when fixtures.status = 'completed' then 0 end,
    'inclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
from (values (
    :'purchaseCanceledID',
    2500,
    now(),
    'USD',
    :'eventCanceledID',
    :'eventCanceledTicketTypeID',
    'completed',
    'General admission',
    :'requesterID',
    'stripe',
    'pi_canceled'
), (
    :'purchaseStartedID',
    2500,
    now(),
    'USD',
    :'eventStartedID',
    :'eventStartedTicketTypeID',
    'completed',
    'General admission',
    :'requesterID',
    null,
    null
), (
    :'purchaseExpiredID',
    2500,
    now() - interval '1 day',
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'expired',
    'General admission',
    :'requesterID',
    null,
    null
), (
    :'purchaseID',
    2500,
    now(),
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'requesterID',
    null,
    null
), (
    :'purchaseNoTeamID',
    2500,
    now(),
    'USD',
    :'eventNoTeamID',
    :'eventNoTeamTicketTypeID',
    'completed',
    'General admission',
    :'requesterID',
    null,
    null
), (
    :'purchaseUnpublishedID',
    2500,
    now(),
    'USD',
    :'eventUnpublishedID',
    :'eventUnpublishedTicketTypeID',
    'completed',
    'General admission',
    :'requesterID',
    null,
    null
)) as fixtures (
    event_purchase_id,
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,
    payment_provider_id,
    provider_payment_reference
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create a refund request and enqueue organizer notifications
select lives_ok(
    format($$select request_event_refund(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        '  Cannot attend  ',
        '{"event":"refund"}'::jsonb
    )$$, :'communityID', :'eventID', :'requesterID'),
    'Should create a refund request and enqueue organizer notifications'
);

-- Should persist the updated purchase and refund request fields
select results_eq(
    format($$
        select
            (select status from event_purchase where event_purchase_id = %L::uuid),
            (select requested_by_user_id from event_refund_request where event_purchase_id = %L::uuid),
            (select requested_reason from event_refund_request where event_purchase_id = %L::uuid),
            (select status from event_refund_request where event_purchase_id = %L::uuid)
    $$, :'purchaseID', :'purchaseID', :'purchaseID', :'purchaseID'),
    format(
        $$ values ('refund-requested'::text, %L::uuid, 'Cannot attend'::text, 'pending'::text) $$,
        :'requesterID'
    ),
    'Should persist the updated purchase and refund request fields'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            community_id,
            event_id,
            group_id,
            details->>'event_purchase_id',
            details->>'user_id'
        from audit_log
    $$,
    format($$ values (
        'event_refund_requested'::text,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L::uuid,
        %L,
        %L
    ) $$, :'requesterID', :'communityID', :'eventID', :'groupID', :'purchaseID', :'requesterID'),
    'Should create the expected audit row'
);

-- Should only enqueue notifications for verified users who can review refunds
select results_eq(
    $$
        select u.username, n.kind, td.data
        from notification n
        join "user" u on u.user_id = n.user_id
        join notification_template_data td using (notification_template_data_id)
        order by u.username
    $$,
    $$ values
        ('community-manager'::text, 'event-refund-requested'::text, '{"event":"refund"}'::jsonb),
        ('organizer-1'::text, 'event-refund-requested'::text, '{"event":"refund"}'::jsonb)
    $$,
    'Should only enqueue notifications for verified users who can review refunds'
);

-- Should reject a refund request after cancellation queues the automatic refund
select cancel_event(:'teamUser1ID', :'groupID', :'eventCanceledID');

select throws_ok(
    format($$select request_event_refund(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null,
        '{"scenario":"request-event-refund"}'::jsonb
    )$$, :'communityID', :'eventCanceledID', :'requesterID'),
    'OCG01',
    'purchase not found or not refundable',
    'Should reject a redundant request after automatic cancellation refund starts'
);

-- Should allow refund requests after the event is unpublished
update event
set published = false
where event_id = :'eventUnpublishedID'::uuid;

select lives_ok(
    format($$select request_event_refund(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null,
        '{"scenario":"request-event-refund"}'::jsonb
    )$$, :'communityID', :'eventUnpublishedID', :'requesterID'),
    'Should allow refund requests after the event is unpublished'
);

-- Should reject refund requests after the event has started
select throws_ok(
    format($$select request_event_refund(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null,
        '{"scenario":"request-event-refund"}'::jsonb
    )$$, :'communityID', :'eventStartedID', :'requesterID'),
    'OCG01',
    'purchase not found or not refundable',
    'Should reject refund requests after the event has started'
);

-- Should reject duplicate refund requests
select throws_ok(
    format($$select request_event_refund(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null,
        '{"scenario":"request-event-refund"}'::jsonb
    )$$, :'communityID', :'eventID', :'requesterID'),
    'OCG01',
    'refund request already exists for this purchase',
    'Should reject duplicate refund requests'
);

-- Should reject refund requests when no organizer recipients exist
select throws_ok(
    format($$select request_event_refund(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null,
        '{"scenario":"request-event-refund"}'::jsonb
    )$$, :'communityNoReviewID', :'eventNoTeamID', :'requesterID'),
    'refund request notification has no recipients',
    'Should reject refund requests when no organizer recipients exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
