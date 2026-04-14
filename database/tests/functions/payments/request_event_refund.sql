-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '78000000-0000-0000-0000-000000000001'
\set eventCategoryID '78000000-0000-0000-0000-000000000002'
\set eventID '78000000-0000-0000-0000-000000000003'
\set eventNoTeamID '78000000-0000-0000-0000-000000000004'
\set eventTicketTypeID '78000000-0000-0000-0000-000000000005'
\set groupCategoryID '78000000-0000-0000-0000-000000000006'
\set groupID '78000000-0000-0000-0000-000000000007'
\set groupNoTeamID '78000000-0000-0000-0000-000000000008'
\set priceWindowID '78000000-0000-0000-0000-000000000009'
\set purchaseExpiredID '78000000-0000-0000-0000-000000000016'
\set purchaseID '78000000-0000-0000-0000-000000000010'
\set purchaseNoTeamID '78000000-0000-0000-0000-000000000011'
\set refundRequestID '78000000-0000-0000-0000-000000000012'
\set requesterID '78000000-0000-0000-0000-000000000013'
\set teamUser1ID '78000000-0000-0000-0000-000000000014'
\set teamUser2ID '78000000-0000-0000-0000-000000000015'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'request-community', 'Request Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'requesterID', 'hash-1', 'requester@example.com', true, 'requester'),
    (:'teamUser1ID', 'hash-2', 'team1@example.com', true, 'organizer-1'),
    (:'teamUser2ID', 'hash-3', 'team2@example.com', true, 'organizer-2');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'groupID', :'communityID', :'groupCategoryID', 'Refund Group', 'refund-group'),
    (:'groupNoTeamID', :'communityID', :'groupCategoryID', 'No Team Group', 'no-team-group');

-- Group team
insert into group_team (group_id, user_id, accepted, role) values
    (:'groupID', :'teamUser1ID', true, 'admin'),
    (:'groupID', :'teamUser2ID', true, 'admin');

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
    :'eventNoTeamID',
    :'eventCategoryID',
    'in-person',
    :'groupNoTeamID',
    'No Team Event',
    'no-team-event',
    'Test event',
    'UTC',
    now() + interval '2 days',
    true,
    now()
);

-- Ticket type and price window
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values
    (:'eventTicketTypeID', :'eventID', 1, 10, 'General admission'),
    ('78000000-0000-0000-0000-000000000099', :'eventNoTeamID', 1, 10, 'General admission');

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    2500,
    :'eventTicketTypeID'
), (
    '78000000-0000-0000-0000-000000000098',
    2500,
    '78000000-0000-0000-0000-000000000099'
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

-- Should enqueue one notification per accepted verified group team member
select results_eq(
    $$
        select u.username, n.kind, td.data
        from notification n
        join "user" u on u.user_id = n.user_id
        join notification_template_data td using (notification_template_data_id)
        order by u.username
    $$,
    $$ values
        ('organizer-1'::text, 'event-refund-requested'::text, '{"event":"refund"}'::jsonb),
        ('organizer-2'::text, 'event-refund-requested'::text, '{"event":"refund"}'::jsonb)
    $$,
    'Should enqueue one notification per accepted verified group team member'
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
        '78000000-0000-0000-0000-000000000001'::uuid,
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
