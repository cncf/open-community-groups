-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '78000000-0000-0000-0000-000000000001'
\set communityNoReviewID '78000000-0000-0000-0000-000000000019'
\set eventCategoryID '78000000-0000-0000-0000-000000000002'
\set eventCanceledID '78000000-0000-0000-0000-000000000022'
\set eventCanceledTicketTypeID '78000000-0000-0000-0000-000000000023'
\set eventCategoryNoReviewID '78000000-0000-0000-0000-000000000020'
\set eventID '78000000-0000-0000-0000-000000000003'
\set eventNoTeamID '78000000-0000-0000-0000-000000000004'
\set eventTicketTypeID '78000000-0000-0000-0000-000000000005'
\set eventUnpublishedID '78000000-0000-0000-0000-000000000024'
\set eventUnpublishedTicketTypeID '78000000-0000-0000-0000-000000000025'
\set groupCategoryID '78000000-0000-0000-0000-000000000006'
\set groupCategoryNoReviewID '78000000-0000-0000-0000-000000000021'
\set communityManagerID '78000000-0000-0000-0000-000000000017'
\set communityViewerID '78000000-0000-0000-0000-000000000018'
\set groupID '78000000-0000-0000-0000-000000000007'
\set groupNoTeamID '78000000-0000-0000-0000-000000000008'
\set priceWindowID '78000000-0000-0000-0000-000000000009'
\set purchaseExpiredID '78000000-0000-0000-0000-000000000016'
\set purchaseID '78000000-0000-0000-0000-000000000010'
\set purchaseCanceledID '78000000-0000-0000-0000-000000000026'
\set purchaseNoTeamID '78000000-0000-0000-0000-000000000011'
\set purchaseUnpublishedID '78000000-0000-0000-0000-000000000027'
\set refundRequestID '78000000-0000-0000-0000-000000000012'
\set requesterID '78000000-0000-0000-0000-000000000013'
\set teamUser1ID '78000000-0000-0000-0000-000000000014'
\set teamUser2ID '78000000-0000-0000-0000-000000000015'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values
    (:'communityID', 'request-community', 'Request Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png'),
    (:'communityNoReviewID', 'no-review-community', 'No Review Community', 'Test', 'https://e/logo-2.png', 'https://e/banner-mobile-2.png', 'https://e/banner-2.png');

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
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'communityManagerID', 'hash-4', 'manager@example.com', true, 'community-manager'),
    (:'communityViewerID', 'hash-5', 'viewer@example.com', true, 'community-viewer'),
    (:'requesterID', 'hash-1', 'requester@example.com', true, 'requester'),
    (:'teamUser1ID', 'hash-2', 'team1@example.com', true, 'organizer-1'),
    (:'teamUser2ID', 'hash-3', 'team2@example.com', true, 'organizer-2');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'groupID', :'communityID', :'groupCategoryID', 'Refund Group', 'refund-group'),
    (:'groupNoTeamID', :'communityNoReviewID', :'groupCategoryNoReviewID', 'No Team Group', 'no-team-group');

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
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values
    (:'eventCanceledTicketTypeID', :'eventCanceledID', 1, 10, 'General admission'),
    (:'eventTicketTypeID', :'eventID', 1, 10, 'General admission'),
    ('78000000-0000-0000-0000-000000000099', :'eventNoTeamID', 1, 10, 'General admission'),
    (:'eventUnpublishedTicketTypeID', :'eventUnpublishedID', 1, 10, 'General admission');

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    '78000000-0000-0000-0000-000000000096',
    2500,
    :'eventCanceledTicketTypeID'
), (
    :'priceWindowID',
    2500,
    :'eventTicketTypeID'
), (
    '78000000-0000-0000-0000-000000000098',
    2500,
    '78000000-0000-0000-0000-000000000099'
), (
    '78000000-0000-0000-0000-000000000097',
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
    '78000000-0000-0000-0000-000000000099'::uuid,
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
    $$select request_event_refund(
        '78000000-0000-0000-0000-000000000001'::uuid,
        '78000000-0000-0000-0000-000000000003'::uuid,
        '78000000-0000-0000-0000-000000000013'::uuid,
        'Cannot attend',
        '{"event":"refund"}'::jsonb
    )$$,
    'Should create a refund request and enqueue organizer notifications'
);

-- Should persist the updated purchase and refund request fields
select results_eq(
    $$
        select
            (select status from event_purchase where event_purchase_id = '78000000-0000-0000-0000-000000000010'::uuid),
            (select requested_by_user_id from event_refund_request where event_purchase_id = '78000000-0000-0000-0000-000000000010'::uuid),
            (select requested_reason from event_refund_request where event_purchase_id = '78000000-0000-0000-0000-000000000010'::uuid),
            (select status from event_refund_request where event_purchase_id = '78000000-0000-0000-0000-000000000010'::uuid)
    $$,
    $$ values ('refund-requested'::text, '78000000-0000-0000-0000-000000000013'::uuid, 'Cannot attend'::text, 'pending'::text) $$,
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
    $$ values (
        'event_refund_requested'::text,
        '78000000-0000-0000-0000-000000000013'::uuid,
        '78000000-0000-0000-0000-000000000001'::uuid,
        '78000000-0000-0000-0000-000000000003'::uuid,
        '78000000-0000-0000-0000-000000000007'::uuid,
        '78000000-0000-0000-0000-000000000010',
        '78000000-0000-0000-0000-000000000013'
    ) $$,
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
    $$select request_event_refund(
        '78000000-0000-0000-0000-000000000001'::uuid,
        '78000000-0000-0000-0000-000000000022'::uuid,
        '78000000-0000-0000-0000-000000000013'::uuid,
        null,
        '{}'::jsonb
    )$$,
    'Should allow refund requests after the event is canceled'
);

-- Should allow refund requests after the event is unpublished
update event
set published = false
where event_id = :'eventUnpublishedID'::uuid;

select lives_ok(
    $$select request_event_refund(
        '78000000-0000-0000-0000-000000000001'::uuid,
        '78000000-0000-0000-0000-000000000024'::uuid,
        '78000000-0000-0000-0000-000000000013'::uuid,
        null,
        '{}'::jsonb
    )$$,
    'Should allow refund requests after the event is unpublished'
);

-- Should reject duplicate refund requests
select throws_ok(
    $$select request_event_refund(
        '78000000-0000-0000-0000-000000000001'::uuid,
        '78000000-0000-0000-0000-000000000003'::uuid,
        '78000000-0000-0000-0000-000000000013'::uuid,
        null,
        '{}'::jsonb
    )$$,
    'refund request already exists for this purchase',
    'Should reject duplicate refund requests'
);

-- Should reject refund requests when no organizer recipients exist
select throws_ok(
    $$select request_event_refund(
        '78000000-0000-0000-0000-000000000019'::uuid,
        '78000000-0000-0000-0000-000000000004'::uuid,
        '78000000-0000-0000-0000-000000000013'::uuid,
        null,
        '{}'::jsonb
    )$$,
    'refund request notification has no recipients',
    'Should reject refund requests when no organizer recipients exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
