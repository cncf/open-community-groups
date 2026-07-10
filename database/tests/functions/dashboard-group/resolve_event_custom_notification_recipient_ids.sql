-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a190000-0000-0000-0000-000000000001'
\set eventCategoryID '3a190000-0000-0000-0000-000000000002'
\set eventID '3a190000-0000-0000-0000-000000000003'
\set groupCategoryID '3a190000-0000-0000-0000-000000000004'
\set groupID '3a190000-0000-0000-0000-000000000005'
\set otherEventID '3a190000-0000-0000-0000-000000000006'
\set otherGroupID '3a190000-0000-0000-0000-000000000007'
\set eligibleUserID '3a190000-0000-0000-0000-000000000008'
\set optedOutUserID '3a190000-0000-0000-0000-000000000009'
\set otherEventUserID '3a190000-0000-0000-0000-000000000012'
\set pendingCheckoutEventID '3a190000-0000-0000-0000-000000000014'
\set pendingCheckoutPurchaseID '3a190000-0000-0000-0000-000000000016'
\set pendingCheckoutTicketTypeID '3a190000-0000-0000-0000-000000000015'
\set pendingCheckoutUserID '3a190000-0000-0000-0000-000000000017'
\set pendingQuestionsUserID '3a190000-0000-0000-0000-000000000013'
\set pendingUserID '3a190000-0000-0000-0000-000000000011'
\set unverifiedUserID '3a190000-0000-0000-0000-000000000010'

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
) values (
    :'communityID',
    'custom-recipient-community',
    'Custom Recipient Community',
    'Community used for custom recipient tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Categories
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category owned by the notification event's community
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Custom Recipient Group', 'custom-recipient-group'),
    (:'otherGroupID', :'communityID', :'groupCategoryID', 'Other Group', 'other-group');

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
    published
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Custom Recipient Event',
    'custom-recipient-event',
    'Custom recipient test event',
    'UTC',
    true
), (
    :'otherEventID',
    :'eventCategoryID',
    'in-person',
    :'otherGroupID',
    'Other Event',
    'other-event',
    'Other event',
    'UTC',
    true
), (
    :'pendingCheckoutEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Pending Checkout Event',
    'pending-checkout-event',
    'Pending checkout event',
    'UTC',
    true
);

-- Ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'pendingCheckoutTicketTypeID',
    :'pendingCheckoutEventID',
    1,
    100,
    'General admission'
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    optional_notifications_enabled,
    username
) values
    (:'eligibleUserID', gen_random_bytes(32), 'eligible@example.com', true, true, 'eligible'),
    (:'optedOutUserID', gen_random_bytes(32), 'opted-out@example.com', true, false, 'opted-out'),
    (:'otherEventUserID', gen_random_bytes(32), 'other@example.com', true, true, 'other'),
    (:'pendingCheckoutUserID', gen_random_bytes(32), 'pending-checkout@example.com', true, true, 'pending-checkout'),
    (:'pendingQuestionsUserID', gen_random_bytes(32), 'questions-pending@example.com', true, true, 'questions-pending'),
    (:'pendingUserID', gen_random_bytes(32), 'pending@example.com', true, true, 'pending'),
    (:'unverifiedUserID', gen_random_bytes(32), 'unverified@example.com', false, true, 'unverified');

-- Attendees
insert into event_attendee (event_id, user_id, status)
values
    (:'eventID', :'eligibleUserID', 'confirmed'),
    (:'eventID', :'optedOutUserID', 'confirmed'),
    (:'otherEventID', :'otherEventUserID', 'confirmed'),
    (:'pendingCheckoutEventID', :'pendingCheckoutUserID', 'registration-questions-pending'),
    (:'eventID', :'pendingQuestionsUserID', 'registration-questions-pending'),
    (:'eventID', :'pendingUserID', 'invitation-pending'),
    (:'eventID', :'unverifiedUserID', 'confirmed');

-- Pending checkout purchase
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
    :'pendingCheckoutPurchaseID',
    2500,
    'USD',
    0,
    :'pendingCheckoutEventID',
    :'pendingCheckoutTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'pendingCheckoutUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should resolve all eligible custom notification recipients.
select is(
    resolve_event_custom_notification_recipient_ids(
        :'groupID'::uuid,
        :'eventID'::uuid,
        'all-attendees',
        null::uuid[]
    ),
    array[:'eligibleUserID'::uuid, :'pendingQuestionsUserID'::uuid],
    'Should resolve all eligible custom notification recipients'
);

-- Should resolve only requested eligible custom notification recipients.
select is(
    resolve_event_custom_notification_recipient_ids(
        :'groupID'::uuid,
        :'eventID'::uuid,
        'selected-attendees',
        array[
            :'eligibleUserID'::uuid,
            :'optedOutUserID'::uuid,
            :'pendingQuestionsUserID'::uuid,
            :'pendingUserID'::uuid
        ]
    ),
    array[:'eligibleUserID'::uuid, :'pendingQuestionsUserID'::uuid],
    'Should resolve only requested eligible custom notification recipients'
);

-- Should deduplicate requested recipients.
select is(
    resolve_event_custom_notification_recipient_ids(
        :'groupID'::uuid,
        :'eventID'::uuid,
        'selected-attendees',
        array[:'eligibleUserID'::uuid, :'eligibleUserID'::uuid]
    ),
    array[:'eligibleUserID'::uuid],
    'Should deduplicate requested recipients'
);

-- Should return empty list when requested recipients are not eligible.
select is(
    resolve_event_custom_notification_recipient_ids(
        :'groupID'::uuid,
        :'eventID'::uuid,
        'selected-attendees',
        array[:'optedOutUserID'::uuid, :'unverifiedUserID'::uuid, :'pendingUserID'::uuid]
    ),
    array[]::uuid[],
    'Should return empty list when requested recipients are not eligible'
);

-- Should return empty list when wrong group_id is provided.
select is(
    resolve_event_custom_notification_recipient_ids(
        :'otherGroupID'::uuid,
        :'eventID'::uuid,
        'all-attendees',
        null::uuid[]
    ),
    array[]::uuid[],
    'Should return empty list when wrong group_id is provided'
);

-- Should return empty list for an unknown recipient scope.
select is(
    resolve_event_custom_notification_recipient_ids(
        :'groupID'::uuid,
        :'eventID'::uuid,
        'unknown-scope',
        null::uuid[]
    ),
    array[]::uuid[],
    'Should return empty list for an unknown recipient scope'
);

-- Should exclude active pending checkout holds from custom notification recipients.
select is(
    resolve_event_custom_notification_recipient_ids(
        :'groupID'::uuid,
        :'pendingCheckoutEventID'::uuid,
        'all-attendees',
        null::uuid[]
    ),
    array[]::uuid[],
    'Should exclude active pending checkout holds from custom notification recipients'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
