-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000009901'
\set categoryInactiveCommunityID '00000000-0000-0000-0000-000000009914'
\set communityID '00000000-0000-0000-0000-000000009902'
\set communityInactiveID '00000000-0000-0000-0000-000000009915'
\set eventDeletedGroupID '00000000-0000-0000-0000-000000009916'
\set eventDisabledID '00000000-0000-0000-0000-000000009903'
\set eventDueID '00000000-0000-0000-0000-000000009904'
\set eventInactiveCommunityID '00000000-0000-0000-0000-000000009917'
\set eventInactiveGroupID '00000000-0000-0000-0000-000000009918'
\set eventNoRecipientsID '00000000-0000-0000-0000-000000009905'
\set eventNotDueID '00000000-0000-0000-0000-000000009906'
\set eventSentID '00000000-0000-0000-0000-000000009907'
\set groupCategoryID '00000000-0000-0000-0000-000000009908'
\set groupCategoryInactiveCommunityID '00000000-0000-0000-0000-000000009919'
\set groupDeletedID '00000000-0000-0000-0000-000000009920'
\set groupID '00000000-0000-0000-0000-000000009909'
\set groupInactiveCommunityID '00000000-0000-0000-0000-000000009921'
\set groupInactiveID '00000000-0000-0000-0000-000000009922'
\set userVerifiedAttendeeID '00000000-0000-0000-0000-000000009910'
\set userVerifiedLateSignupID '00000000-0000-0000-0000-000000009911'
\set userVerifiedSpeakerID '00000000-0000-0000-0000-000000009912'
\set userUnverifiedID '00000000-0000-0000-0000-000000009913'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Site settings
insert into site (site_id, title, description, theme) values (
    '00000000-0000-0000-0000-000000009900',
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
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'Reminder notification tests',
    'https://example.com/community-logo.png',
    'https://example.com/community-banner-mobile.png',
    'https://example.com/community-banner.png'
);

-- Inactive community
insert into community (
    community_id,
    active,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityInactiveID',
    false,
    'inactive-community',
    'Inactive Community',
    'Inactive community used for reminder tests',
    'https://example.com/inactive-community-logo.png',
    'https://example.com/inactive-community-banner-mobile.png',
    'https://example.com/inactive-community-banner.png'
);

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Group category for inactive community
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryInactiveCommunityID', 'Design', :'communityInactiveID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'categoryID', 'General', :'communityID');

-- Event category for inactive community
insert into event_category (event_category_id, name, community_id)
values (:'categoryInactiveCommunityID', 'Community', :'communityInactiveID');

-- Group
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id,
    logo_url
) values (
    :'groupID',
    :'communityID',
    'Test Group',
    'test-group',
    'Group used for reminder tests',
    :'groupCategoryID',
    'https://example.com/group-logo.png'
);

-- Inactive and deleted groups
insert into "group" (
    group_id,
    active,
    community_id,
    name,
    slug,
    description,
    deleted,
    group_category_id,
    logo_url
) values
    (
        :'groupDeletedID',
        false,
        :'communityID',
        'Deleted Group',
        'deleted-group',
        'Deleted group used for reminder tests',
        true,
        :'groupCategoryID',
        'https://example.com/deleted-group-logo.png'
    ),
    (
        :'groupInactiveID',
        false,
        :'communityID',
        'Inactive Group',
        'inactive-group',
        'Inactive group used for reminder tests',
        false,
        :'groupCategoryID',
        'https://example.com/inactive-group-logo.png'
    );

-- Group in inactive community
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id,
    logo_url
) values (
    :'groupInactiveCommunityID',
    :'communityInactiveID',
    'Inactive Community Group',
    'inactive-community-group',
    'Group in inactive community used for reminder tests',
    :'groupCategoryInactiveCommunityID',
    'https://example.com/inactive-community-group-logo.png'
);

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'userVerifiedAttendeeID', 'hash-1', 'attendee@example.com', true, 'attendee'),
    (:'userVerifiedLateSignupID', 'hash-2', 'late-signup@example.com', true, 'late-signup'),
    (:'userVerifiedSpeakerID', 'hash-3', 'speaker@example.com', true, 'speaker'),
    (:'userUnverifiedID', 'hash-4', 'unverified@example.com', false, 'unverified');

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
        :'categoryID',
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
        :'categoryID',
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
        :'categoryID',
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
        :'categoryID',
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
        :'categoryInactiveCommunityID',
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
        :'categoryID',
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
    :'categoryID',
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
    :'categoryID',
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
insert into event_attendee (event_id, user_id) values
    (:'eventDueID', :'userVerifiedAttendeeID'),
    (:'eventDeletedGroupID', :'userVerifiedAttendeeID'),
    (:'eventInactiveCommunityID', :'userVerifiedAttendeeID'),
    (:'eventInactiveGroupID', :'userVerifiedAttendeeID'),
    (:'eventDueID', :'userUnverifiedID');

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
    $$
    select n.user_id
    from notification n
    join notification_template_data ntd using (notification_template_data_id)
    where n.kind = 'event-reminder'
    and ntd.data->'event'->>'event_id' = '00000000-0000-0000-0000-000000009904'
    order by n.user_id
    $$,
    $$ values
        ('00000000-0000-0000-0000-000000009910'::uuid),
        ('00000000-0000-0000-0000-000000009912'::uuid)
    $$,
    'Should create one reminder notification per verified recipient for the due event'
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
    'https://example.test/test-community/group/test-group/event/due-event',
    'Should build reminder link using the provided base URL'
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
