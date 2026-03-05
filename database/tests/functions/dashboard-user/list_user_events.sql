-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

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

\set eventAID '00000000-0000-0000-0000-000000000101'
\set eventBID '00000000-0000-0000-0000-000000000102'
\set eventCanceledID '00000000-0000-0000-0000-000000000103'
\set eventCID '00000000-0000-0000-0000-000000000104'
\set eventDeletedID '00000000-0000-0000-0000-000000000105'
\set eventInactiveGroupID '00000000-0000-0000-0000-000000000106'
\set eventNoStartsAtID '00000000-0000-0000-0000-000000000107'
\set eventPastID '00000000-0000-0000-0000-000000000108'
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
    (:'userID', 'auth-hash', 'alice@example.com', true, 'alice', 'Alice');

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
    );

-- Sessions for speaker role tests
insert into session (session_id, event_id, name, session_kind_id, starts_at) values
    (:'sessionAID', :'eventAID', 'Session A', 'virtual', '2099-01-10 11:00:00+00'),
    (:'sessionCID', :'eventCID', 'Session C', 'virtual', '2099-01-12 11:00:00+00');

-- User participation
insert into event_attendee (event_id, user_id) values
    (:'eventAID', :'userID'),
    (:'eventBID', :'userID'),
    (:'eventCanceledID', :'userID'),
    (:'eventDeletedGroupID', :'userID'),
    (:'eventDeletedID', :'userID'),
    (:'eventInactiveGroupID', :'userID'),
    (:'eventNoStartsAtID', :'userID'),
    (:'eventPastID', :'userID'),
    (:'eventUnpublishedID', :'userID');

insert into event_host (event_id, user_id) values
    (:'eventAID', :'userID');

insert into event_speaker (event_id, user_id, featured) values
    (:'eventAID', :'userID', true);

insert into session_speaker (session_id, user_id, featured) values
    (:'sessionAID', :'userID', false),
    (:'sessionCID', :'userID', true);

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
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventAID'::uuid)::jsonb,
                'roles',
                jsonb_build_array('Attendee', 'Host', 'Speaker')
            ),
            jsonb_build_object(
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventBID'::uuid)::jsonb,
                'roles',
                jsonb_build_array('Attendee')
            ),
            jsonb_build_object(
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
