-- Tests composing the analytics of an event owned by a group.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(19);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ea0a0000-0000-0000-0000-000000000001'
\set eventCategoryID 'ea0a0000-0000-0000-0000-000000000002'
\set eventDeletedID 'ea0a0000-0000-0000-0000-000000000003'
\set eventForeignID 'ea0a0000-0000-0000-0000-000000000004'
\set eventFutureID 'ea0a0000-0000-0000-0000-000000000005'
\set eventOngoingID 'ea0a0000-0000-0000-0000-000000000006'
\set eventPastID 'ea0a0000-0000-0000-0000-000000000007'
\set eventPublishedLateID 'ea0a0000-0000-0000-0000-000000000008'
\set eventUnpublishedID 'ea0a0000-0000-0000-0000-000000000009'
\set groupCategoryID 'ea0a0000-0000-0000-0000-00000000000a'
\set groupForeignID 'ea0a0000-0000-0000-0000-00000000000b'
\set groupID 'ea0a0000-0000-0000-0000-00000000000c'
\set priceWindowID 'ea0a0000-0000-0000-0000-00000000000d'
\set ticketTypeID 'ea0a0000-0000-0000-0000-00000000000e'
\set userAttendeeID 'ea0a0000-0000-0000-0000-00000000000f'
\set userOrganizerID 'ea0a0000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupForeignID', :'communityID', :'groupCategoryID');
select fx_user(:'userAttendeeID');
select fx_user(:'userOrganizerID');

-- Deleted event of the group
select fx_event(:'eventDeletedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'deleted_at', current_timestamp
));

-- Event of another group
select fx_event(:'eventForeignID', :'groupForeignID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', current_timestamp - interval '2 days'
));

-- Free future event
select fx_event(:'eventFutureID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '5 days' + interval '2 hours',
    'published', true,
    'published_at', current_timestamp - interval '2 days',
    'starts_at', current_timestamp + interval '5 days'
));

-- Ongoing event
select fx_event(:'eventOngoingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 hours',
    'published', true,
    'published_at', current_timestamp - interval '3 days',
    'starts_at', current_timestamp - interval '1 hour'
));

-- Paid past event republished after recording views
select fx_event(:'eventPastID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp - interval '3 days' + interval '2 hours',
    'event_reminder_sent_at', current_timestamp - interval '4 days' + interval '1 hour',
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', current_timestamp - interval '10 days',
    'registration_ends_at', current_timestamp - interval '4 days',
    'registration_starts_at', current_timestamp - interval '9 days',
    'starts_at', current_timestamp - interval '3 days',
    'timezone', 'Europe/Madrid'
));

-- Event published after it ended
select fx_event(:'eventPublishedLateID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '5 days' + interval '2 hours',
    'published', true,
    'published_at', current_timestamp - interval '1 day',
    'starts_at', current_timestamp - interval '5 days'
));

-- Never published event
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', current_timestamp + interval '5 days'
));

-- Paid ticket type of the past event, whose seats set the event capacity
select fx_event_ticket_type(:'ticketTypeID', :'eventPastID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General'
));

-- Paid price window of the past event ticket type
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 1000));

-- Announcements inside the range, one beyond the cap, and one after the range
insert into custom_notification (body, created_at, created_by, event_id, subject)
select
    'Announcement body',
    current_timestamp - interval '5 days' + make_interval(mins => n),
    :'userOrganizerID'::uuid,
    :'eventPastID'::uuid,
    'Announcement'
from generate_series(1, 51) as n
union all
select
    'Late announcement body',
    current_timestamp - interval '1 day',
    :'userOrganizerID'::uuid,
    :'eventPastID'::uuid,
    'Late announcement';

-- Checked-in attendee of the past event
insert into event_attendee (event_id, user_id, checked_in, checked_in_at, created_at) values
    (:'eventPastID', :'userAttendeeID', true, current_timestamp - interval '3 days', current_timestamp - interval '6 days');

-- Views of the past event before and after its publication
insert into event_views (event_id, day, total) values
    (:'eventPastID', ((current_timestamp - interval '12 days') at time zone 'UTC')::date, 5),
    (:'eventPastID', ((current_timestamp - interval '5 days') at time zone 'UTC')::date, 10);

-- Tagged views of the past event
insert into event_views_utm (event_id, day, total, utm_medium, utm_source) values
    (:'eventPastID', ((current_timestamp - interval '5 days') at time zone 'UTC')::date, 4, 'social', 'news');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cap announcement markers at the 50 most recent inside the range
select is(
    (
        select jsonb_build_object(
            'announcements', (
                select count(*)
                from jsonb_array_elements(stats->'markers') as marker
                where marker->>'kind' = 'announcement'
            ),
            'oldest_announcement', (
                select min((marker->>'ts')::bigint)
                from jsonb_array_elements(stats->'markers') as marker
                where marker->>'kind' = 'announcement'
            ),
            'omitted', stats->'markers_announcements_omitted'
        )
        from (select get_event_analytics(:'groupID', :'eventPastID')::jsonb as stats) event_stats
    ),
    jsonb_build_object(
        'announcements', 50,
        'oldest_announcement', epoch_seconds(current_timestamp - interval '5 days' + interval '2 minutes'),
        'omitted', 1
    ),
    'Should cap announcement markers at the 50 most recent inside the range'
);

-- Should compose the audience section from its helper
select is(
    get_event_analytics(:'groupID', :'eventPastID')::jsonb->'audience',
    (
        select stats_event_audience(e)::jsonb
        from event e
        where e.event_id = :'eventPastID'
    ),
    'Should compose the audience section from its helper'
);

-- Should compose the check-in section from its helper
select is(
    get_event_analytics(:'groupID', :'eventPastID')::jsonb->'check_ins',
    (
        select stats_event_check_ins(e)::jsonb
        from event e
        where e.event_id = :'eventPastID'
    ),
    'Should compose the check-in section from its helper'
);

-- Should compose the enrollment section from its helper
select is(
    get_event_analytics(:'groupID', :'eventPastID')::jsonb->'enrollment',
    (
        select stats_event_enrollment(e)::jsonb
        from event e
        where e.event_id = :'eventPastID'
    ),
    'Should compose the enrollment section from its helper'
);

-- Should compose the ticket section from its helper
select is(
    get_event_analytics(:'groupID', :'eventPastID')::jsonb->'tickets',
    (
        select stats_event_tickets(e)::jsonb
        from event e
        where e.event_id = :'eventPastID'
    ),
    'Should compose the ticket section from its helper'
);

-- Should compose the traffic section from its helper
select is(
    get_event_analytics(:'groupID', :'eventPastID')::jsonb->'traffic',
    (
        select stats_event_traffic(
            e,
            (e.published_at at time zone 'UTC')::date,
            (e.ends_at at time zone 'UTC')::date
        )::jsonb
        from event e
        where e.event_id = :'eventPastID'
    ),
    'Should compose the traffic section from its helper'
);

-- Should compose the UTM section from its helper
select is(
    get_event_analytics(:'groupID', :'eventPastID')::jsonb->'utm',
    (
        select stats_event_utm(e)::jsonb
        from event e
        where e.event_id = :'eventPastID'
    ),
    'Should compose the UTM section from its helper'
);

-- Should end the range at the earlier of today and the end of ongoing events
select is(
    get_event_analytics(:'groupID', :'eventOngoingID')::jsonb->'range',
    jsonb_build_object(
        'end_day', least(to_char((current_timestamp) at time zone 'UTC', 'YYYY-MM-DD'), to_char((current_timestamp + interval '2 hours') at time zone 'UTC', 'YYYY-MM-DD')),
        'start_day', to_char((current_timestamp - interval '3 days') at time zone 'UTC', 'YYYY-MM-DD')
    ),
    'Should end the range at the earlier of today and the end of ongoing events'
);

-- Should end the range at the effective end of past events
select is(
    get_event_analytics(:'groupID', :'eventPastID')::jsonb->'range',
    jsonb_build_object(
        'end_day', to_char((current_timestamp - interval '3 days' + interval '2 hours') at time zone 'UTC', 'YYYY-MM-DD'),
        'start_day', to_char((current_timestamp - interval '10 days') at time zone 'UTC', 'YYYY-MM-DD')
    ),
    'Should end the range at the effective end of past events'
);

-- Should end the range today for future events
select is(
    get_event_analytics(:'groupID', :'eventFutureID')::jsonb->'range',
    jsonb_build_object(
        'end_day', to_char((current_timestamp) at time zone 'UTC', 'YYYY-MM-DD'),
        'start_day', to_char((current_timestamp - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD')
    ),
    'Should end the range today for future events'
);

-- Should exclude markers after the end of the range
select is(
    get_event_analytics(:'groupID', :'eventFutureID')::jsonb->'markers',
    jsonb_build_array(
        jsonb_build_object('kind', 'published', 'ts', epoch_seconds(current_timestamp - interval '2 days'))
    ),
    'Should exclude markers after the end of the range'
);

-- Should include lifecycle markers inside the range
select is(
    (
        select jsonb_agg(marker order by ordinality)
        from jsonb_array_elements(get_event_analytics(:'groupID', :'eventPastID')::jsonb->'markers')
            with ordinality as markers(marker, ordinality)
        where marker->>'kind' <> 'announcement'
    ),
    jsonb_build_array(
        jsonb_build_object('kind', 'published', 'ts', epoch_seconds(current_timestamp - interval '10 days')),
        jsonb_build_object('kind', 'registration-opens', 'ts', epoch_seconds(current_timestamp - interval '9 days')),
        jsonb_build_object('kind', 'registration-closes', 'ts', epoch_seconds(current_timestamp - interval '4 days')),
        jsonb_build_object('kind', 'reminder-sent', 'ts', epoch_seconds(current_timestamp - interval '4 days' + interval '1 hour')),
        jsonb_build_object('kind', 'event-start', 'ts', epoch_seconds(current_timestamp - interval '3 days'))
    ),
    'Should include lifecycle markers inside the range'
);

-- Should report the event configuration
select is(
    get_event_analytics(:'groupID', :'eventPastID')::jsonb->'event',
    jsonb_build_object(
        'canceled', false,
        'is_paid', true,
        'published', true,
        'timezone', 'Europe/Madrid',

        'capacity', 100,
        'ends_at', epoch_seconds(current_timestamp - interval '3 days' + interval '2 hours'),
        'published_at', epoch_seconds(current_timestamp - interval '10 days'),
        'registration_ends_at', epoch_seconds(current_timestamp - interval '4 days'),
        'registration_starts_at', epoch_seconds(current_timestamp - interval '9 days'),
        'starts_at', epoch_seconds(current_timestamp - interval '3 days')
    ),
    'Should report the event configuration'
);

-- Should report views recorded before the publication of republished events
select is(
    (get_event_analytics(:'groupID', :'eventPastID')::jsonb->'traffic'->>'views_before_start')::int,
    5,
    'Should report views recorded before the publication of republished events'
);

-- Should return a null range and no markers for never published events
select is(
    (
        select jsonb_build_object('markers', stats->'markers', 'range', stats->'range')
        from (select get_event_analytics(:'groupID', :'eventUnpublishedID')::jsonb as stats) event_stats
    ),
    '{"markers": [], "range": null}'::jsonb,
    'Should return a null range and no markers for never published events'
);

-- Should return a null range for events published after they ended
select is(
    get_event_analytics(:'groupID', :'eventPublishedLateID')::jsonb->'range',
    'null'::jsonb,
    'Should return a null range for events published after they ended'
);

-- Should return null for deleted events
select is(
    get_event_analytics(:'groupID', :'eventDeletedID')::jsonb,
    null::jsonb,
    'Should return null for deleted events'
);

-- Should return null for events of another group
select is(
    get_event_analytics(:'groupID', :'eventForeignID')::jsonb,
    null::jsonb,
    'Should return null for events of another group'
);

-- Should return null tickets for free events
select is(
    get_event_analytics(:'groupID', :'eventFutureID')::jsonb->'tickets',
    'null'::jsonb,
    'Should return null tickets for free events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
