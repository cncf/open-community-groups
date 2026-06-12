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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
)
values
    (
        :'communityID',
        'request-community',
        'Request Community',
        'Test',
        'https://e/banner-mobile.png',
        'https://e/banner.png',
        'https://e/logo.png'
    ),
    (
        :'communityNoReviewID',
        'no-review-community',
        'No Review Community',
        'Test',
        'https://e/banner-mobile-2.png',
        'https://e/banner-2.png',
        'https://e/logo-2.png'
    );

-- Group category
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategoryID', :'communityID', 'Tech'),
    (:'groupCategoryNoReviewID', :'communityNoReviewID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values
    (:'eventCategoryID', :'communityID', 'General'),
    (:'eventCategoryNoReviewID', :'communityNoReviewID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (
        :'communityManagerID',
        'hash-4',
        'manager@example.com',
        true,
        'community-manager'
    ),
    (
        :'communityViewerID',
        'hash-5',
        'viewer@example.com',
        true,
        'community-viewer'
    ),
    (
        :'requesterID',
        'hash-1',
        'requester@example.com',
        true,
        'requester'
    ),
    (
        :'teamUser1ID',
        'hash-2',
        'team1@example.com',
        true,
        'organizer-1'
    ),
    (
        :'teamUser2ID',
        'hash-3',
        'team2@example.com',
        true,
        'organizer-2'
    );

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug)
values
    (
        :'groupID',
        :'communityID',
        :'groupCategoryID',
        'Refund Group',
        'refund-group'
    ),
    (
        :'groupNoTeamID',
        :'communityNoReviewID',
        :'groupCategoryNoReviewID',
        'No Team Group',
        'no-team-group'
    );

-- Group team
insert into group_team (group_id, user_id, accepted, role) values
    (:'groupID', :'teamUser1ID', true, 'admin'),
    (:'groupID', :'teamUser2ID', true, 'viewer');

-- Community team
insert into community_team (accepted, community_id, role, user_id) values
    (true, :'communityID', 'groups-manager', :'communityManagerID'),
    (true, :'communityID', 'viewer', :'communityViewerID');

-- Events
insert into event (
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
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Refund Event',
    'refund-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    true,
    now()
), (
    :'eventStartedID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Started Refund Event',
    'started-refund-event',
    'Test event',
    'UTC',
    now() - interval '1 hour',
    true,
    now()
), (
    :'eventCanceledID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Canceled Refund Event',
    'canceled-refund-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    true,
    now()
), (
    :'eventNoTeamID',
    :'eventCategoryNoReviewID',
    'in-person',
    :'groupNoTeamID',
    'No Team Event',
    'no-team-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    true,
    now()
), (
    :'eventUnpublishedID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Unpublished Refund Event',
    'unpublished-refund-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    true,
    now()
);

-- Ticket type and price window
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
)
values
    (
        :'eventCanceledTicketTypeID',
        :'eventCanceledID',
        1,
        10,
        'General admission'
    ),
    (
        :'eventNoTeamTicketTypeID',
        :'eventNoTeamID',
        1,
        10,
        'General admission'
    ),
    (
        :'eventStartedTicketTypeID',
        :'eventStartedID',
        1,
        10,
        'General admission'
    ),
    (
        :'eventTicketTypeID',
        :'eventID',
        1,
        10,
        'General admission'
    ),
    (
        :'eventUnpublishedTicketTypeID',
        :'eventUnpublishedID',
        1,
        10,
        'General admission'
    );

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowCanceledID',
    2500,
    :'eventCanceledTicketTypeID'
), (
    :'priceWindowNoTeamID',
    2500,
    :'eventNoTeamTicketTypeID'
), (
    :'priceWindowStartedID',
    2500,
    :'eventStartedTicketTypeID'
), (
    :'priceWindowID',
    2500,
    :'eventTicketTypeID'
), (
    :'priceWindowUnpublishedID',
    2500,
    :'eventUnpublishedTicketTypeID'
);

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
    user_id
) values (
    :'purchaseCanceledID',
    2500,
    now(),
    'USD',
    :'eventCanceledID',
    :'eventCanceledTicketTypeID',
    'completed',
    'General admission',
    :'requesterID'
), (
    :'purchaseStartedID',
    2500,
    now(),
    'USD',
    :'eventStartedID',
    :'eventStartedTicketTypeID',
    'completed',
    'General admission',
    :'requesterID'
), (
    :'purchaseExpiredID',
    2500,
    now() - interval '1 day',
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'expired',
    'General admission',
    :'requesterID'
), (
    :'purchaseID',
    2500,
    now(),
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'requesterID'
), (
    :'purchaseNoTeamID',
    2500,
    now(),
    'USD',
    :'eventNoTeamID',
    :'eventNoTeamTicketTypeID',
    'completed',
    'General admission',
    :'requesterID'
), (
    :'purchaseUnpublishedID',
    2500,
    now(),
    'USD',
    :'eventUnpublishedID',
    :'eventUnpublishedTicketTypeID',
    'completed',
    'General admission',
    :'requesterID'
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
        'Cannot attend',
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

-- Should allow refund requests after the event is canceled
update event
set
    canceled = true,
    published = false
where event_id = :'eventCanceledID'::uuid;

select lives_ok(
    format($$select request_event_refund(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        null,
        '{}'::jsonb
    )$$, :'communityID', :'eventCanceledID', :'requesterID'),
    'Should allow refund requests after the event is canceled'
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
        '{}'::jsonb
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
        '{}'::jsonb
    )$$, :'communityID', :'eventStartedID', :'requesterID'),
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
        '{}'::jsonb
    )$$, :'communityID', :'eventID', :'requesterID'),
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
        '{}'::jsonb
    )$$, :'communityNoReviewID', :'eventNoTeamID', :'requesterID'),
    'refund request notification has no recipients',
    'Should reject refund requests when no organizer recipients exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
