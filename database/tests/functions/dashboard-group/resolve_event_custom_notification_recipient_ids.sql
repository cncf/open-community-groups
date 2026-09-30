-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a080000-0000-0000-0000-000000000001'
\set eventCategoryID '3a080000-0000-0000-0000-000000000002'
\set eventID '3a080000-0000-0000-0000-000000000003'
\set groupCategoryID '3a080000-0000-0000-0000-000000000004'
\set groupID '3a080000-0000-0000-0000-000000000005'
\set otherEventID '3a080000-0000-0000-0000-000000000006'
\set otherGroupID '3a080000-0000-0000-0000-000000000007'
\set eligibleUserID '3a080000-0000-0000-0000-000000000008'
\set optedOutUserID '3a080000-0000-0000-0000-000000000009'
\set ownerMutedUserID '3a080000-0000-0000-0000-000000000018'
\set otherEventUserID '3a080000-0000-0000-0000-000000000012'
\set pendingCheckoutEventID '3a080000-0000-0000-0000-000000000014'
\set pendingCheckoutPurchaseID '3a080000-0000-0000-0000-000000000016'
\set pendingCheckoutTicketTypeID '3a080000-0000-0000-0000-000000000015'
\set pendingCheckoutUserID '3a080000-0000-0000-0000-000000000017'
\set pendingQuestionsUserID '3a080000-0000-0000-0000-000000000013'
\set pendingUserID '3a080000-0000-0000-0000-000000000011'
\set unrelatedMutedUserID '3a080000-0000-0000-0000-000000000019'
\set unverifiedUserID '3a080000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_user(:'pendingCheckoutUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Event category owned by the notification event's community
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'General'));

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'otherEventID', :'otherGroupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'pendingCheckoutEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Ticket types
select fx_event_ticket_type(:'pendingCheckoutTicketTypeID', :'pendingCheckoutEventID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General admission'
));

-- Users
select fx_user(:'eligibleUserID', jsonb_build_object('username', 'eligible'));
select fx_user(:'optedOutUserID');
select fx_user(:'otherEventUserID', jsonb_build_object('username', 'other'));
select fx_user(:'ownerMutedUserID');
select fx_user(:'pendingQuestionsUserID', jsonb_build_object('username', 'questions-pending'));
select fx_user(:'pendingUserID', jsonb_build_object('username', 'pending'));
select fx_user(:'unrelatedMutedUserID');
select fx_user(:'unverifiedUserID', jsonb_build_object(
    'email_verified', false,
    'username', 'unverified-resolve-event-custom-notification-recipient-ids'
));

-- Attendees
insert into event_attendee (event_id, user_id, status)
values
    (:'eventID', :'eligibleUserID', 'confirmed'),
    (:'eventID', :'optedOutUserID', 'confirmed'),
    (:'eventID', :'ownerMutedUserID', 'confirmed'),
    (:'otherEventID', :'otherEventUserID', 'confirmed'),
    (:'pendingCheckoutEventID', :'pendingCheckoutUserID', 'registration-questions-pending'),
    (:'eventID', :'pendingQuestionsUserID', 'registration-questions-pending'),
    (:'eventID', :'pendingUserID', 'invitation-pending'),
    (:'eventID', :'unrelatedMutedUserID', 'confirmed'),
    (:'eventID', :'unverifiedUserID', 'confirmed');

-- Organizer messages opt-out used by recipient preference filtering
insert into user_notification_opt_out (notification_category_id, user_id)
values ('organizer-messages', :'optedOutUserID');

-- Owner group mute used by recipient preference filtering
insert into user_group_notification_mute (group_id, user_id)
values (:'groupID', :'ownerMutedUserID');

-- Unrelated group mute that should not affect this event
insert into user_group_notification_mute (group_id, user_id)
values (:'otherGroupID', :'unrelatedMutedUserID');

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

-- Should resolve all eligible custom notification recipients.
select is(
    resolve_event_custom_notification_recipient_ids(
        :'groupID'::uuid,
        :'eventID'::uuid,
        'all-attendees',
        null::uuid[]
    ),
    array[:'eligibleUserID'::uuid, :'pendingQuestionsUserID'::uuid, :'unrelatedMutedUserID'::uuid],
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
            :'ownerMutedUserID'::uuid,
            :'optedOutUserID'::uuid,
            :'pendingQuestionsUserID'::uuid,
            :'pendingUserID'::uuid,
            :'unrelatedMutedUserID'::uuid
        ]
    ),
    array[:'eligibleUserID'::uuid, :'pendingQuestionsUserID'::uuid, :'unrelatedMutedUserID'::uuid],
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
        array[:'optedOutUserID'::uuid, :'ownerMutedUserID'::uuid, :'unverifiedUserID'::uuid, :'pendingUserID'::uuid]
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
