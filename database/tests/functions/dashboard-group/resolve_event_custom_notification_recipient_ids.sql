-- Tests resolving event custom email recipients for a recipient scope.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a080000-0000-0000-0000-000000000001'
\set eligibleUserID '3a080000-0000-0000-0000-000000000008'
\set eventCategoryID '3a080000-0000-0000-0000-000000000002'
\set eventID '3a080000-0000-0000-0000-000000000003'
\set groupCategoryID '3a080000-0000-0000-0000-000000000004'
\set groupID '3a080000-0000-0000-0000-000000000005'
\set otherGroupID '3a080000-0000-0000-0000-000000000007'
\set pendingCheckoutEventID '3a080000-0000-0000-0000-000000000014'
\set pendingCheckoutPurchaseID '3a080000-0000-0000-0000-000000000016'
\set pendingCheckoutTicketTypeID '3a080000-0000-0000-0000-000000000015'
\set pendingCheckoutUserID '3a080000-0000-0000-0000-000000000017'
\set pendingQuestionsUserID '3a080000-0000-0000-0000-000000000013'
\set pendingUserID '3a080000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the groups under test
select fx_community(:'communityID');

-- Eligible confirmed attendee
select fx_user(:'eligibleUserID', jsonb_build_object('username', 'eligible'));

-- Attendee holding a live pending checkout
select fx_user(:'pendingCheckoutUserID');

-- Eligible attendee with pending registration questions
select fx_user(:'pendingQuestionsUserID', jsonb_build_object('username', 'questions-pending'));

-- Ineligible attendee with a pending invitation
select fx_user(:'pendingUserID', jsonb_build_object('username', 'pending'));

-- Event category owned by the notification event's community
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'General'));

-- Group category for every group under test
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the events under test
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group that does not own the events under test
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Event whose attendees are resolved by scope
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Event whose only attendee holds a live pending checkout
select fx_event(:'pendingCheckoutEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Attendees covering eligible, ineligible and live checkout states
insert into event_attendee (event_id, user_id, status)
values
    (:'eventID', :'eligibleUserID', 'confirmed'),
    (:'eventID', :'pendingQuestionsUserID', 'registration-questions-pending'),
    (:'eventID', :'pendingUserID', 'invitation-pending'),
    (:'pendingCheckoutEventID', :'pendingCheckoutUserID', 'registration-questions-pending');

-- Ticket type used by the pending checkout purchase
select fx_event_ticket_type(:'pendingCheckoutTicketTypeID', :'pendingCheckoutEventID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General admission'
));

-- Pending checkout purchase with a live hold
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
    0,
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

-- Should deduplicate requested recipients
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

-- Should exclude active pending checkout holds from custom notification recipients
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

-- Should resolve all eligible custom notification recipients
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

-- Should resolve only requested eligible custom notification recipients
select is(
    resolve_event_custom_notification_recipient_ids(
        :'groupID'::uuid,
        :'eventID'::uuid,
        'selected-attendees',
        array[:'pendingQuestionsUserID'::uuid, :'pendingUserID'::uuid]
    ),
    array[:'pendingQuestionsUserID'::uuid],
    'Should resolve only requested eligible custom notification recipients'
);

-- Should return empty list for an unknown recipient scope
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

-- Should return empty list when requested recipients are not eligible
select is(
    resolve_event_custom_notification_recipient_ids(
        :'groupID'::uuid,
        :'eventID'::uuid,
        'selected-attendees',
        array[:'pendingUserID'::uuid]
    ),
    array[]::uuid[],
    'Should return empty list when requested recipients are not eligible'
);

-- Should return empty list when wrong group_id is provided
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
