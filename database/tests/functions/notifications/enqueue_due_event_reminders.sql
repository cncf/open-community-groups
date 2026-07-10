-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '8a020000-0000-0000-0000-000000000001'
\set communityInactiveID '8a020000-0000-0000-0000-000000000002'
\set eventCategoryID '8a020000-0000-0000-0000-000000000003'
\set eventCategoryInactiveCommunityID '8a020000-0000-0000-0000-000000000004'
\set eventDeletedGroupID '8a020000-0000-0000-0000-000000000005'
\set eventDisabledID '8a020000-0000-0000-0000-000000000006'
\set eventDueID '8a020000-0000-0000-0000-000000000007'
\set eventInactiveCommunityID '8a020000-0000-0000-0000-000000000008'
\set eventInactiveGroupID '8a020000-0000-0000-0000-000000000009'
\set eventNoRecipientsID '8a020000-0000-0000-0000-000000000010'
\set eventNotDueID '8a020000-0000-0000-0000-000000000011'
\set eventSentID '8a020000-0000-0000-0000-000000000012'
\set groupCategoryID '8a020000-0000-0000-0000-000000000013'
\set groupCategoryInactiveCommunityID '8a020000-0000-0000-0000-000000000014'
\set groupDeletedID '8a020000-0000-0000-0000-000000000015'
\set groupID '8a020000-0000-0000-0000-000000000016'
\set groupInactiveCommunityID '8a020000-0000-0000-0000-000000000017'
\set groupInactiveID '8a020000-0000-0000-0000-000000000018'
\set siteID '8a020000-0000-0000-0000-000000000019'
\set userPreRegisteredInvitedID '8a020000-0000-0000-0000-000000000020'
\set userUnverifiedID '8a020000-0000-0000-0000-000000000021'
\set userVerifiedAttendeeID '8a020000-0000-0000-0000-000000000022'
\set userVerifiedLateSignupID '8a020000-0000-0000-0000-000000000023'
\set userVerifiedSpeakerID '8a020000-0000-0000-0000-000000000024'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Site settings
insert into site (site_id, title, description, theme) values (
    :'siteID',
    'Test Site',
    'Test Site Description',
    '{"primary_color": "#2563eb"}'::jsonb
);

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
    'event-reminders-community',
    'Event Reminders Community',
    'Reminder notification tests',
    'https://example.com/community-banner-mobile.png',
    'https://example.com/community-banner.png',
    'https://example.com/community-logo.png'
);

-- Inactive community
insert into community (
    community_id,
    name,
    display_name,
    description,
    active,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityInactiveID',
    'inactive-community',
    'Inactive Community',
    'Inactive community used for reminder tests',
    false,
    'https://example.com/inactive-community-banner-mobile.png',
    'https://example.com/inactive-community-banner.png',
    'https://example.com/inactive-community-logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group category for inactive community
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryInactiveCommunityID', :'communityInactiveID', 'Design');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Event category for inactive community
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryInactiveCommunityID', :'communityInactiveID', 'Community');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    slug_pretty,
    description,
    logo_url
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'test-group-pretty',
    'Group used for reminder tests',
    'https://example.com/group-logo.png'
);

-- Inactive and deleted groups
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    active,
    deleted,
    description,
    logo_url
) values
    (
        :'groupDeletedID',
        :'communityID',
        :'groupCategoryID',
        'Deleted Group',
        'deleted-group',
        false,
        true,
        'Deleted group used for reminder tests',
        'https://example.com/deleted-group-logo.png'
    ),
    (
        :'groupInactiveID',
        :'communityID',
        :'groupCategoryID',
        'Inactive Group',
        'inactive-group',
        false,
        false,
        'Inactive group used for reminder tests',
        'https://example.com/inactive-group-logo.png'
    );

-- Group in inactive community
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description,
    logo_url
) values (
    :'groupInactiveCommunityID',
    :'communityInactiveID',
    :'groupCategoryInactiveCommunityID',
    'Inactive Community Group',
    'inactive-community-group',
    'Group in inactive community used for reminder tests',
    'https://example.com/inactive-community-group-logo.png'
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    registration_status
) values
    (:'userVerifiedAttendeeID', 'hash-1', 'attendee@example.com', true, 'attendee', 'registered'),
    (:'userVerifiedLateSignupID', 'hash-2', 'late-signup@example.com',
        true, 'late-signup', 'registered'),
    (:'userVerifiedSpeakerID', 'hash-3', 'speaker@example.com', true, 'speaker', 'registered'),
    (:'userUnverifiedID', 'hash-4', 'unverified@example.com', false, 'unverified', 'registered'),
    (:'userPreRegisteredInvitedID', 'hash-5', 'invited@example.com',
        false, 'invited', 'pre-registered');

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published,
    venue_city,
    venue_country_code,
    venue_country_name,
    venue_name
) values
    (
        :'eventDueID',
        :'groupID',
        'Due Event',
        'due-event',
        'Event that should trigger reminders',
        'UTC',
        :'eventCategoryID',
        'hybrid',
        current_timestamp + interval '23 hours',
        current_timestamp + interval '24 hours',
        true,
        'Seattle',
        'US',
        'United States',
        'Conference Hall'
    ),
    (
        :'eventNoRecipientsID',
        :'groupID',
        'No Recipients Event',
        'no-recipients-event',
        'Due event without verified recipients',
        'UTC',
        :'eventCategoryID',
        'virtual',
        current_timestamp + interval '20 hours',
        current_timestamp + interval '21 hours',
        true,
        'Austin',
        'US',
        'United States',
        'Remote'
    ),
    (
        :'eventNotDueID',
        :'groupID',
        'Not Due Event',
        'not-due-event',
        'Event outside reminder window',
        'UTC',
        :'eventCategoryID',
        'in-person',
        current_timestamp + interval '30 hours',
        current_timestamp + interval '31 hours',
        true,
        'Boston',
        'US',
        'United States',
        'Center'
    ),
    (
        :'eventDeletedGroupID',
        :'groupDeletedID',
        'Deleted Group Event',
        'deleted-group-event',
        'Due event from a deleted group',
        'UTC',
        :'eventCategoryID',
        'virtual',
        current_timestamp + interval '19 hours',
        current_timestamp + interval '20 hours',
        true,
        'San Francisco',
        'US',
        'United States',
        'Remote'
    ),
    (
        :'eventInactiveCommunityID',
        :'groupInactiveCommunityID',
        'Inactive Community Event',
        'inactive-community-event',
        'Due event from an inactive community',
        'UTC',
        :'eventCategoryInactiveCommunityID',
        'virtual',
        current_timestamp + interval '18 hours',
        current_timestamp + interval '19 hours',
        true,
        'Portland',
        'US',
        'United States',
        'Remote'
    ),
    (
        :'eventInactiveGroupID',
        :'groupInactiveID',
        'Inactive Group Event',
        'inactive-group-event',
        'Due event from an inactive group',
        'UTC',
        :'eventCategoryID',
        'virtual',
        current_timestamp + interval '17 hours',
        current_timestamp + interval '18 hours',
        true,
        'San Diego',
        'US',
        'United States',
        'Remote'
    );

-- Event with reminders disabled
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published,
    event_reminder_enabled,
    venue_city,
    venue_country_code,
    venue_country_name,
    venue_name
) values (
    :'eventDisabledID',
    :'groupID',
    'Disabled Reminder Event',
    'disabled-reminder-event',
    'Event with reminders disabled',
    'UTC',
    :'eventCategoryID',
    'in-person',
    current_timestamp + interval '20 hours',
    current_timestamp + interval '21 hours',
    true,
    false,
    'Denver',
    'US',
    'United States',
    'Center'
);

-- Event with reminder already sent
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published,
    event_reminder_sent_at,
    venue_city,
    venue_country_code,
    venue_country_name,
    venue_name
) values (
    :'eventSentID',
    :'groupID',
    'Already Sent Event',
    'already-sent-event',
    'Event with reminder already sent',
    'UTC',
    :'eventCategoryID',
    'in-person',
    current_timestamp + interval '20 hours',
    current_timestamp + interval '21 hours',
    true,
    current_timestamp,
    'Chicago',
    'US',
    'United States',
    'Center'
);

-- Attendees and speakers for due event
insert into event_attendee (event_id, user_id, status) values
    (:'eventDueID', :'userVerifiedAttendeeID', 'confirmed'),
    (:'eventDeletedGroupID', :'userVerifiedAttendeeID', 'confirmed'),
    (:'eventInactiveCommunityID', :'userVerifiedAttendeeID', 'confirmed'),
    (:'eventInactiveGroupID', :'userVerifiedAttendeeID', 'confirmed'),
    (:'eventDueID', :'userUnverifiedID', 'confirmed'),
    (:'eventDueID', :'userPreRegisteredInvitedID', 'invitation-pending');

-- Event speakers considered by reminder recipient selection
insert into event_speaker (event_id, user_id, featured) values
    (:'eventDueID', :'userVerifiedSpeakerID', true),
    (:'eventDueID', :'userVerifiedAttendeeID', false),
    (:'eventDueID', :'userUnverifiedID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should enqueue reminders for verified attendees and speakers on due events
select is(
    enqueue_due_event_reminders('https://example.test/'),
    2,
    'Should enqueue reminders for verified attendees and speakers on due events'
);

-- Should create one reminder notification per verified recipient for the due event
select results_eq(
    format(
        $$
    select n.user_id
    from notification n
    join notification_template_data ntd using (notification_template_data_id)
    where n.kind = 'event-reminder'
    and ntd.data->'event'->>'event_id' = %L
    order by n.user_id
        $$,
        :'eventDueID'
    ),
    format(
        $$ values
        (%L::uuid),
        (%L::uuid)
        $$,
        :'userVerifiedAttendeeID',
        :'userVerifiedSpeakerID'
    ),
    'Should create one reminder notification per verified recipient for the due event'
);

-- Should not enqueue reminders for pending invitation rows
select is(
    (
        select count(*)::int
        from notification
        where kind = 'event-reminder'
        and user_id = :'userPreRegisteredInvitedID'::uuid
    ),
    0,
    'Should not enqueue reminders for pending invitation rows'
);

-- Should build reminder link using the provided base URL
select is(
    (
        select ntd.data->>'link'
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-reminder'
        limit 1
    ),
    'https://example.test/event-reminders-community/group/test-group-pretty/event/due-event',
    'Should build reminder link using the provided base URL'
);

-- Should build dashboard link using the provided base URL
select is(
    (
        select ntd.data->>'dashboard_link'
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-reminder'
        limit 1
    ),
    'https://example.test/dashboard/user?tab=events',
    'Should build dashboard link using the provided base URL'
);

-- Should show attendance cancellation copy for attendee recipients
select is(
    (
        select ntd.data->>'show_attendance_cancellation_copy'
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-reminder'
        and n.user_id = :'userVerifiedAttendeeID'::uuid
    ),
    'true',
    'Should show attendance cancellation copy for attendee recipients'
);

-- Should prevent speaker-only recipients from seeing cancellation reminder copy
select is(
    (
        select ntd.data->>'show_attendance_cancellation_copy'
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-reminder'
        and n.user_id = :'userVerifiedSpeakerID'::uuid
    ),
    'false',
    'Should prevent speaker-only recipients from seeing cancellation reminder copy'
);

-- Should include waitlist fields in reminder template data
select is(
    (
        select jsonb_build_object(
            'waitlist_count', ntd.data->'event'->'waitlist_count',
            'waitlist_enabled', ntd.data->'event'->'waitlist_enabled'
        )
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-reminder'
        limit 1
    ),
    '{"waitlist_count": 0, "waitlist_enabled": false}'::jsonb,
    'Should include waitlist fields in reminder template data'
);

-- Should include the latest site theme in reminder template data
select is(
    (
        select ntd.data->'theme'
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-reminder'
        limit 1
    ),
    '{"primary_color": "#2563eb"}'::jsonb,
    'Should include the latest site theme in reminder template data'
);

-- Should mark due event as evaluated for its current start date
select is(
    (select event_reminder_evaluated_for_starts_at from event where event_id = :'eventDueID'),
    (select starts_at from event where event_id = :'eventDueID'),
    'Should mark due event as evaluated for its current start date'
);

-- Should set reminder sent timestamp on due event when notifications are queued
select isnt(
    (select event_reminder_sent_at from event where event_id = :'eventDueID'),
    null::timestamptz,
    'Should set reminder sent timestamp on due event when notifications are queued'
);

-- Should mark no-recipients event as evaluated even when nothing is enqueued
select is(
    (select event_reminder_evaluated_for_starts_at from event where event_id = :'eventNoRecipientsID'),
    (select starts_at from event where event_id = :'eventNoRecipientsID'),
    'Should mark no-recipients event as evaluated even when nothing is enqueued'
);

-- Should not set reminder sent timestamp when no recipients are found
select is(
    (select event_reminder_sent_at from event where event_id = :'eventNoRecipientsID'),
    null::timestamptz,
    'Should not set reminder sent timestamp when no recipients are found'
);

-- Should skip not due, disabled, already sent, and inactive/deleted entity events
select is(
    (
        select count(*)
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-reminder'
        and ntd.data->'event'->>'event_id' in (
            :'eventDeletedGroupID',
            :'eventNotDueID',
            :'eventDisabledID',
            :'eventInactiveCommunityID',
            :'eventInactiveGroupID',
            :'eventSentID'
        )
    ),
    0::bigint,
    'Should skip not due, disabled, already sent, and inactive/deleted entity events'
);

-- Should enqueue no additional notifications when run again
select is(
    enqueue_due_event_reminders('https://example.test'),
    0,
    'Should enqueue no additional notifications when run again'
);

-- Should keep no-recipients event ignored after late signup
insert into event_attendee (event_id, user_id)
values (:'eventNoRecipientsID', :'userVerifiedLateSignupID');
select is(
    enqueue_due_event_reminders('https://example.test'),
    0,
    'Should keep no-recipients event ignored after late signup'
);

-- Should not create reminders for late signups after the event was evaluated
select is(
    (
        select count(*)
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-reminder'
        and ntd.data->'event'->>'event_id' = :'eventNoRecipientsID'
    ),
    0::bigint,
    'Should not create reminders for late signups after the event was evaluated'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
