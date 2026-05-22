-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000011'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupDeletedID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000032'
\set groupInactiveID '00000000-0000-0000-0000-000000000033'
\set userEmptyID '00000000-0000-0000-0000-000000000099'
\set userID '00000000-0000-0000-0000-000000000081'
\set userPaidID '00000000-0000-0000-0000-000000000082'

\set eventAID '00000000-0000-0000-0000-000000000101'
\set eventBID '00000000-0000-0000-0000-000000000102'
\set eventCanceledID '00000000-0000-0000-0000-000000000103'
\set eventCID '00000000-0000-0000-0000-000000000104'
\set eventDeletedID '00000000-0000-0000-0000-000000000105'
\set eventInactiveGroupID '00000000-0000-0000-0000-000000000106'
\set eventNoStartsAtID '00000000-0000-0000-0000-000000000107'
\set eventPastID '00000000-0000-0000-0000-000000000108'
\set eventPendingInvitationID '00000000-0000-0000-0000-000000000111'
\set eventPaidID '00000000-0000-0000-0000-000000000112'
\set eventPaidPriceWindowID '00000000-0000-0000-0000-000000000115'
\set eventPaidPurchaseID '00000000-0000-0000-0000-000000000113'
\set eventPaidTicketTypeID '00000000-0000-0000-0000-000000000114'
\set eventUnpublishedID '00000000-0000-0000-0000-000000000109'
\set eventDeletedGroupID '00000000-0000-0000-0000-000000000110'

\set sessionAID '00000000-0000-0000-0000-000000000201'
\set sessionCID '00000000-0000-0000-0000-000000000202'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (
        :'communityID',
        'community-one',
        'Community One',
        'Test community',
        'https://e/logo.png',
        'https://e/banner-mobile.png',
        'https://e/banner.png'
    );

-- Group category
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name) values
    (:'eventCategoryID', :'communityID', 'Meetup');

-- Groups
insert into "group" (group_id, active, community_id, deleted, group_category_id, name, slug) values
    (:'groupDeletedID', false, :'communityID', true, :'groupCategoryID', 'Deleted Group', 'deleted-group'),
    (:'groupID', true, :'communityID', false, :'groupCategoryID', 'Main Group', 'main-group'),
    (:'groupInactiveID', false, :'communityID', false, :'groupCategoryID', 'Inactive Group', 'inactive-group');

-- User
insert into "user" (user_id, auth_hash, email, email_verified, username, name) values
    (:'userID', 'auth-hash', 'alice@example.com', true, 'alice', 'Alice'),
    (:'userPaidID', 'paid-auth-hash', 'paid@example.com', true, 'paid', 'Paid User');

-- Events
insert into event (
    event_id,
    canceled,
    deleted,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values
    (
        :'eventAID',
        false,
        false,
        'Event A',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Event A',
        true,
        'event-a',
        '2099-01-10 10:00:00+00',
        'UTC'
    ),
    (
        :'eventBID',
        false,
        false,
        'Event B',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event B',
        true,
        'event-b',
        '2099-01-11 10:00:00+00',
        'UTC'
    ),
    (
        :'eventCanceledID',
        true,
        false,
        'Event Canceled',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event Canceled',
        false,
        'event-canceled',
        '2099-01-13 10:00:00+00',
        'UTC'
    ),
    (
        :'eventCID',
        false,
        false,
        'Event C',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event C',
        true,
        'event-c',
        '2099-01-12 10:00:00+00',
        'UTC'
    ),
    (
        :'eventDeletedID',
        false,
        true,
        'Event Deleted',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event Deleted',
        false,
        'event-deleted',
        '2099-01-14 10:00:00+00',
        'UTC'
    ),
    (
        :'eventInactiveGroupID',
        false,
        false,
        'Event Inactive Group',
        :'eventCategoryID',
        'virtual',
        :'groupInactiveID',
        'Event Inactive Group',
        true,
        'event-inactive-group',
        '2099-01-15 10:00:00+00',
        'UTC'
    ),
    (
        :'eventNoStartsAtID',
        false,
        false,
        'Event No Start',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event No Start',
        true,
        'event-no-start',
        null,
        'UTC'
    ),
    (
        :'eventPastID',
        false,
        false,
        'Event Past',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event Past',
        true,
        'event-past',
        '2000-01-01 10:00:00+00',
        'UTC'
    ),
    (
        :'eventPendingInvitationID',
        false,
        false,
        'Event Pending Invitation',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event Pending Invitation',
        true,
        'event-pending-invitation',
        '2099-01-13 12:00:00+00',
        'UTC'
    ),
    (
        :'eventUnpublishedID',
        false,
        false,
        'Event Unpublished',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Event Unpublished',
        false,
        'event-unpublished',
        '2099-01-16 10:00:00+00',
        'UTC'
    ),
    (
        :'eventDeletedGroupID',
        false,
        false,
        'Event Deleted Group',
        :'eventCategoryID',
        'virtual',
        :'groupDeletedID',
        'Event Deleted Group',
        true,
        'event-deleted-group',
        '2099-01-17 10:00:00+00',
        'UTC'
    ),
    (
        :'eventPaidID',
        false,
        false,
        'Event Paid',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Event Paid',
        true,
        'event-paid',
        '2099-01-18 10:00:00+00',
        'UTC'
    );

update event
set payment_currency_code = 'USD'
where event_id = :'eventPaidID'::uuid;

-- Sessions for speaker role tests
insert into session (session_id, event_id, name, session_kind_id, starts_at) values
    (:'sessionAID', :'eventAID', 'Session A', 'virtual', '2099-01-10 11:00:00+00'),
    (:'sessionCID', :'eventCID', 'Session C', 'virtual', '2099-01-12 11:00:00+00');

-- Event ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'eventPaidTicketTypeID',
    :'eventPaidID',
    1,
    1,
    'Paid admission'
);

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'eventPaidPriceWindowID',
    1500,
    :'eventPaidTicketTypeID'
);

-- User participation
insert into event_attendee (event_id, user_id, status) values
    (:'eventAID', :'userID', 'confirmed'),
    (:'eventBID', :'userID', 'confirmed'),
    (:'eventCanceledID', :'userID', 'confirmed'),
    (:'eventDeletedGroupID', :'userID', 'confirmed'),
    (:'eventDeletedID', :'userID', 'confirmed'),
    (:'eventInactiveGroupID', :'userID', 'confirmed'),
    (:'eventNoStartsAtID', :'userID', 'confirmed'),
    (:'eventPastID', :'userID', 'confirmed'),
    (:'eventPaidID', :'userPaidID', 'confirmed'),
    (:'eventPendingInvitationID', :'userID', 'invitation-pending'),
    (:'eventUnpublishedID', :'userID', 'confirmed');

insert into event_host (event_id, user_id) values
    (:'eventAID', :'userID');

insert into event_speaker (event_id, user_id, featured) values
    (:'eventAID', :'userID', true);

insert into session_speaker (session_id, user_id, featured) values
    (:'sessionAID', :'userID', false),
    (:'sessionCID', :'userID', true);

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'eventPaidPurchaseID',
    1500,
    'USD',
    :'eventPaidID',
    :'eventPaidTicketTypeID',
    'completed',
    'Paid admission',
    :'userPaidID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list only valid upcoming events sorted by date asc
select is(
    list_user_events(:'userID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        jsonb_build_array(
            jsonb_build_object(
                'can_cancel_attendance',
                false,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventAID'::uuid)::jsonb,
                'roles',
                jsonb_build_array('Attendee', 'Host', 'Speaker')
            ),
            jsonb_build_object(
                'can_cancel_attendance',
                true,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventBID'::uuid)::jsonb,
                'roles',
                jsonb_build_array('Attendee')
            ),
            jsonb_build_object(
                'can_cancel_attendance',
                false,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventCID'::uuid)::jsonb,
                'roles',
                jsonb_build_array('Speaker')
            )
        ),
        'total',
        3
    ),
    'Should list only valid upcoming events sorted by date asc'
);

-- Should deduplicate roles per event
select is(
    (
        list_user_events(:'userID'::uuid, '{"limit": 1, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
        -> 'roles'
    ),
    jsonb_build_array('Attendee', 'Host', 'Speaker'),
    'Should deduplicate roles per event'
);

-- Should paginate events and keep total count
select is(
    list_user_events(:'userID'::uuid, '{"limit": 1, "offset": 1}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        jsonb_build_array(
            jsonb_build_object(
                'can_cancel_attendance',
                true,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventBID'::uuid)::jsonb,
                'roles',
                jsonb_build_array('Attendee')
            )
        ),
        'total',
        3
    ),
    'Should paginate events and keep total count'
);

-- Should not allow paid attendee-only events to be canceled from My Events
select is(
    list_user_events(:'userPaidID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        jsonb_build_array(
            jsonb_build_object(
                'can_cancel_attendance',
                false,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventPaidID'::uuid)::jsonb,
                'roles',
                jsonb_build_array('Attendee')
            )
        ),
        'total',
        1
    ),
    'Should not allow paid attendee-only events to be canceled from My Events'
);

-- Should return empty result for users without events
select is(
    list_user_events(:'userEmptyID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        '[]'::jsonb,
        'total',
        0
    ),
    'Should return empty result for users without events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
