-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '79280000-0000-0000-0000-000000000001'
\set eventCategoryID '79280000-0000-0000-0000-000000000002'
\set ticketedEventID '79280000-0000-0000-0000-000000000003'
\set nonTicketedEventID '79280000-0000-0000-0000-000000000004'
\set ticketTypeID '79280000-0000-0000-0000-000000000005'
\set priceWindowID '79280000-0000-0000-0000-000000000006'
\set groupCategoryID '79280000-0000-0000-0000-000000000007'
\set groupID '79280000-0000-0000-0000-000000000008'
\set activePurchaseID '79280000-0000-0000-0000-000000000009'
\set completedPurchaseID '79280000-0000-0000-0000-000000000010'
\set releasedUserID '79280000-0000-0000-0000-000000000011'
\set activeUserID '79280000-0000-0000-0000-000000000012'
\set completedUserID '79280000-0000-0000-0000-000000000013'
\set manualUserID '79280000-0000-0000-0000-000000000014'
\set nonTicketedUserID '79280000-0000-0000-0000-000000000015'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'allianceID', 'release-attendee-hold-alliance', 'Release Attendee Hold Alliance', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Tech');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'releasedUserID', 'hash-1', 'released@example.com', true, 'released-user'),
    (:'activeUserID', 'hash-2', 'active@example.com', true, 'active-user'),
    (:'completedUserID', 'hash-3', 'completed@example.com', true, 'completed-user'),
    (:'manualUserID', 'hash-4', 'manual@example.com', true, 'manual-user'),
    (:'nonTicketedUserID', 'hash-5', 'non-ticketed@example.com', true, 'non-ticketed-user');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, payment_recipient, slug)
values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Release Attendee Hold Group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_release_attendee_hold'),
    'release-attendee-hold-group'
);

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
    payment_currency_code,
    published,
    published_at
) values (
    :'ticketedEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Ticketed Release Event',
    'ticketed-release-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    'USD',
    true,
    now()
), (
    :'nonTicketedEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Non-Ticketed Release Event',
    'non-ticketed-release-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    null,
    true,
    now()
);

-- Ticket type
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'ticketTypeID', :'ticketedEventID', 1, 10, 'General admission');

-- Price window
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    2500,
    :'ticketTypeID'
);

-- Purchases that should protect their attendee rows
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'activePurchaseID',
    2500,
    'USD',
    0,
    :'ticketedEventID',
    :'ticketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'activeUserID'
), (
    :'completedPurchaseID',
    2500,
    'USD',
    0,
    :'ticketedEventID',
    :'ticketTypeID',
    null,
    'completed',
    'General admission',
    :'completedUserID'
);

-- Pending attendee rows
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'ticketedEventID', :'releasedUserID', false, 'registration-questions-pending'),
    (:'ticketedEventID', :'activeUserID', false, 'registration-questions-pending'),
    (:'ticketedEventID', :'completedUserID', false, 'registration-questions-pending'),
    (:'ticketedEventID', :'manualUserID', true, 'registration-questions-pending'),
    (:'nonTicketedEventID', :'nonTicketedUserID', false, 'registration-questions-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should release a checkout-created pending attendee row without an active purchase
select lives_ok(
    $$select release_event_checkout_attendee_hold(
        '79280000-0000-0000-0000-000000000003'::uuid,
        '79280000-0000-0000-0000-000000000011'::uuid
    )$$,
    'Should release a checkout-created pending attendee row without an active purchase'
);

-- Should remove the unprotected checkout-created attendee row
select is(
    (
        select count(*)::int
        from event_attendee
        where event_id = :'ticketedEventID'::uuid
        and user_id = :'releasedUserID'::uuid
    ),
    0,
    'Should remove the unprotected checkout-created attendee row'
);

-- Should leave protected pending attendee rows alone
select lives_ok(
    $$
        select
            release_event_checkout_attendee_hold(
                '79280000-0000-0000-0000-000000000003'::uuid,
                '79280000-0000-0000-0000-000000000012'::uuid
            ),
            release_event_checkout_attendee_hold(
                '79280000-0000-0000-0000-000000000003'::uuid,
                '79280000-0000-0000-0000-000000000013'::uuid
            ),
            release_event_checkout_attendee_hold(
                '79280000-0000-0000-0000-000000000003'::uuid,
                '79280000-0000-0000-0000-000000000014'::uuid
            ),
            release_event_checkout_attendee_hold(
                '79280000-0000-0000-0000-000000000004'::uuid,
                '79280000-0000-0000-0000-000000000015'::uuid
            )
    $$,
    'Should leave protected pending attendee rows alone'
);

-- Should preserve rows protected by active purchases, completed purchases, invitations, or non-ticketed events
select results_eq(
    $$
        select
            (
                select count(*)::int
                from event_attendee
                where event_id = '79280000-0000-0000-0000-000000000003'::uuid
                and user_id = '79280000-0000-0000-0000-000000000012'::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = '79280000-0000-0000-0000-000000000003'::uuid
                and user_id = '79280000-0000-0000-0000-000000000013'::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = '79280000-0000-0000-0000-000000000003'::uuid
                and user_id = '79280000-0000-0000-0000-000000000014'::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = '79280000-0000-0000-0000-000000000004'::uuid
                and user_id = '79280000-0000-0000-0000-000000000015'::uuid
            )
    $$,
    $$ values (1::int, 1::int, 1::int, 1::int) $$,
    'Should preserve rows protected by active purchases, completed purchases, invitations, or non-ticketed events'
);

-- Should be idempotent for already released rows
select lives_ok(
    $$select release_event_checkout_attendee_hold(
        '79280000-0000-0000-0000-000000000003'::uuid,
        '79280000-0000-0000-0000-000000000011'::uuid
    )$$,
    'Should be idempotent for already released rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
