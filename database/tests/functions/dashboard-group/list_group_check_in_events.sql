-- Tests listing current and upcoming events for group check-in scanners.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID '3a2c0000-0000-0000-0000-000000000012'
\set communityID '3a2c0000-0000-0000-0000-000000000001'
\set currentEventID '3a2c0000-0000-0000-0000-000000000002'
\set endedEventID '3a2c0000-0000-0000-0000-000000000008'
\set eventCategoryID '3a2c0000-0000-0000-0000-000000000003'
\set futureEventID '3a2c0000-0000-0000-0000-000000000004'
\set groupCategoryID '3a2c0000-0000-0000-0000-000000000005'
\set groupID '3a2c0000-0000-0000-0000-000000000006'
\set noLogoGroupEventID '3a2c0000-0000-0000-0000-000000000017'
\set noLogoGroupID '3a2c0000-0000-0000-0000-000000000016'
\set startedTodayEventID '3a2c0000-0000-0000-0000-000000000015'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community credited on the co-host card and used as the last logo fallback
select fx_community(:'communityID', jsonb_build_object(
    'display_name', 'Check-in Community',
    'logo_url', 'https://ex.test/check-in-community-logo.png',
    'name', 'check-in-events-community'
));

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Scanner group whose logo is the fallback for events without a logo
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'logo_url', 'https://ex.test/check-in-group-logo.png'
));

-- Approved co-host group credited on the current event
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'logo_url', 'https://ex.test/check-in-cohost-logo.png',
    'name', 'Check-in Cohost',
    'slug', 'check-in-cohost'
));

-- Group without a logo, falling back to the community logo
select fx_group(:'noLogoGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('logo_url', null));

-- In-progress event with a full venue and no own logo
select fx_event(:'currentEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 hour',
    'event_kind_id', 'in-person',
    'name', 'Current Meetup',
    'published', true,
    'published_at', current_timestamp - interval '3 hours',
    'starts_at', current_timestamp - interval '2 hours',
    'timezone', 'UTC',
    'venue_city', 'Lisbon',
    'venue_country_name', 'Portugal',
    'venue_name', 'Main Hall',
    'venue_state_name', 'Lisboa'
));

-- Event that explicitly ended at the start of today, excluded by the scanner window
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', date_trunc('day', current_timestamp at time zone 'UTC') at time zone 'UTC',
    'published', true,
    'published_at', current_timestamp - interval '1 day',
    'starts_at', (
                    date_trunc('day', current_timestamp at time zone 'UTC') - interval '1 hour'
                ) at time zone 'UTC'
));

-- Upcoming virtual event with its own logo and no venue
select fx_event(:'futureEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'logo_url', 'https://ex.test/check-in-future-logo.png',
    'name', 'Future Webinar',
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '1 day',
    'timezone', 'UTC'
));

-- Upcoming event without a logo in the group without a logo
select fx_event(:'noLogoGroupEventID', :'noLogoGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '1 day'
));

-- Event started today without an end, listed until local midnight
select fx_event(:'startedTodayEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'hybrid',
    'name', 'Started Today',
    'published', true,
    'published_at', current_timestamp - interval '1 day',
    'starts_at', greatest(
        current_timestamp - interval '1 hour',
        date_trunc('day', current_timestamp at time zone 'UTC') at time zone 'UTC'
    ),
    'timezone', 'UTC',
    'venue_city', 'Porto'
));

-- Approved co-host credited on the current event
insert into event_cohost (event_cohost_status_id, event_id, group_id, approved_at)
values ('approved', :'currentEventID', :'cohostGroupID', current_timestamp);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should fall back to the community logo when the event and group have none
select is(
    list_group_check_in_events(:'noLogoGroupID'::uuid)::jsonb->0->>'logo_url',
    'https://ex.test/check-in-community-logo.png',
    'Should fall back to the community logo when the event and group have none'
);

-- Should list in-progress events before upcoming events with scanner fields
select is(
    list_group_check_in_events(:'groupID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'event_id', :'currentEventID'::uuid,
            'kind', 'in-person',
            'name', 'Current Meetup',
            'starts_at', epoch_seconds(current_timestamp - interval '2 hours'),
            'timezone', 'UTC',
            'cohosts', jsonb_build_array(jsonb_build_object(
                'community_display_name', 'Check-in Community',
                'community_name', 'check-in-events-community',
                'group_id', :'cohostGroupID'::uuid,
                'logo_url', 'https://ex.test/check-in-cohost-logo.png',
                'name', 'Check-in Cohost',
                'slug', 'check-in-cohost'
            )),
            'logo_url', 'https://ex.test/check-in-group-logo.png',
            'location', 'Main Hall, Lisbon, Lisboa, Portugal',
            'in_progress', true
        ),
        jsonb_build_object(
            'event_id', :'startedTodayEventID'::uuid,
            'kind', 'hybrid',
            'name', 'Started Today',
            'starts_at', epoch_seconds(greatest(
                current_timestamp - interval '1 hour',
                date_trunc('day', current_timestamp at time zone 'UTC') at time zone 'UTC'
            )),
            'timezone', 'UTC',
            'cohosts', '[]'::jsonb,
            'logo_url', 'https://ex.test/check-in-group-logo.png',
            'location', 'Porto',
            'in_progress', true
        ),
        jsonb_build_object(
            'event_id', :'futureEventID'::uuid,
            'kind', 'virtual',
            'name', 'Future Webinar',
            'starts_at', epoch_seconds(current_timestamp + interval '1 day'),
            'timezone', 'UTC',
            'cohosts', '[]'::jsonb,
            'logo_url', 'https://ex.test/check-in-future-logo.png',
            'location', null,
            'in_progress', false
        )
    ),
    'Should list in-progress events before upcoming events with scanner fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
