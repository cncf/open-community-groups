-- Tests loading purchase identifiers used to compose notifications.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendeeID 'e07f0000-0000-0000-0000-000000000001'
\set communityID 'e07f0000-0000-0000-0000-000000000002'
\set eventCategoryID 'e07f0000-0000-0000-0000-000000000003'
\set eventID 'e07f0000-0000-0000-0000-000000000004'
\set eventTicketTypeID 'e07f0000-0000-0000-0000-000000000005'
\set groupCategoryID 'e07f0000-0000-0000-0000-000000000006'
\set groupID 'e07f0000-0000-0000-0000-000000000007'
\set otherGroupID 'e07f0000-0000-0000-0000-000000000008'
\set purchaseID 'e07f0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for notification-context scenarios
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'notification-context-community',
    'Notification Context Community',
    'Community for purchase notification context tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category for notification-context scenarios
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category for notification-context scenarios
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group that owns the purchase under test
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    :'groupCategoryID',
    :'groupID',
    'Notification Context Group',
    'notification-context-group'
);

-- Separate group used by the ownership-miss scenario
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    :'groupCategoryID',
    :'otherGroupID',
    'Other Notification Context Group',
    'other-notification-context-group'
);

-- Attendee who owns the purchase
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (
    :'attendeeID',
    'hash-context-attendee',
    'context-attendee@example.test',
    true,
    'context-attendee'
);

-- Published event used by the notification-context scenario
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    timezone
) values (
    'Notification context event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Notification Context Event',
    true,
    'notification-context-event',
    'UTC'
);

-- Ticket type required by the purchase row
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    :'eventID',
    :'eventTicketTypeID',
    1,
    50,
    'General admission'
);

-- Purchase whose identifiers are returned to the notification composer
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    0,
    'ocg-free',
    null,
    :'eventID',
    :'purchaseID',
    :'eventTicketTypeID',
    0,
    0,
    'pending',
    'General admission',
    :'attendeeID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the community and event for a group-owned purchase
select is(
    get_event_purchase_notification_context(
        :'groupID'::uuid,
        :'purchaseID'::uuid
    ),
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid
    ),
    'Should return the community and event for a group-owned purchase'
);

-- Should return null when the purchase belongs to another group
select is(
    get_event_purchase_notification_context(
        :'otherGroupID'::uuid,
        :'purchaseID'::uuid
    ),
    null,
    'Should return null when the purchase belongs to another group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
