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

insert into site (site_id, title, description, theme) values (
    :'siteID',
    'Test Site',
    'Test Site Description',
    '{"primary_color": "#2563eb"}'::jsonb
);

-- Community
select fx_community(:'communityID', jsonb_build_object('name', 'event-reminders-community'));

-- Inactive community
select fx_community(:'communityInactiveID', jsonb_build_object('active', false));

-- Baseline categories, users and groups
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group_category(:'groupCategoryInactiveCommunityID', :'communityInactiveID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userVerifiedLateSignupID');
select fx_group(:'groupInactiveCommunityID', :'communityInactiveID', :'groupCategoryInactiveCommunityID');

-- Event category for inactive community
select fx_event_category(:'eventCategoryInactiveCommunityID', :'communityInactiveID', jsonb_build_object('name', 'Community'));

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'slug', 'test-group',
    'slug_pretty', 'test-group-pretty'
));

-- Inactive and deleted groups
select fx_group(:'groupDeletedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));
-- group
select fx_group(:'groupInactiveID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Users
select fx_user(:'userVerifiedAttendeeID', jsonb_build_object('username', 'attendee-enqueue-due-event-reminders'));
-- user
select fx_user(:'userVerifiedSpeakerID', jsonb_build_object('username', 'speaker-enqueue-due-event-reminders'));
-- user
select fx_user(:'userUnverifiedID', jsonb_build_object('email_verified', false));
-- user
select fx_user(:'userPreRegisteredInvitedID', jsonb_build_object(
    'email_verified', false,
    'registration_status', 'pre-registered'
));

-- Events
select fx_event(:'eventDueID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '24 hours',
    'event_kind_id', 'hybrid',
    'published', true,
    'slug', 'due-event',
    'starts_at', current_timestamp + interval '23 hours',
    'venue_city', 'Seattle',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Conference Hall'
));
-- event
select fx_event(:'eventNoRecipientsID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '21 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', current_timestamp + interval '20 hours',
    'venue_city', 'Austin',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Remote'
));
-- event
select fx_event(:'eventNotDueID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '31 hours',
    'published', true,
    'starts_at', current_timestamp + interval '30 hours',
    'venue_city', 'Boston',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Center'
));
-- event
select fx_event(:'eventDeletedGroupID', :'groupDeletedID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '20 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', current_timestamp + interval '19 hours',
    'venue_city', 'San Francisco',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Remote'
));
-- event
select fx_event(:'eventInactiveCommunityID', :'groupInactiveCommunityID', :'eventCategoryInactiveCommunityID', jsonb_build_object(
    'ends_at', current_timestamp + interval '19 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', current_timestamp + interval '18 hours',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Remote'
));
-- event
select fx_event(:'eventInactiveGroupID', :'groupInactiveID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '18 hours',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', current_timestamp + interval '17 hours',
    'venue_city', 'San Diego',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Remote'
));

-- Event with reminders disabled
select fx_event(:'eventDisabledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '21 hours',
    'event_reminder_enabled', false,
    'published', true,
    'starts_at', current_timestamp + interval '20 hours',
    'venue_city', 'Denver',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Center'
));

-- Event with reminder already sent
select fx_event(:'eventSentID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '21 hours',
    'event_reminder_sent_at', current_timestamp,
    'published', true,
    'starts_at', current_timestamp + interval '20 hours',
    'venue_city', 'Chicago',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Center'
));

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
