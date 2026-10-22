-- Tests updating event dates and sessions.
-- Split from update_event.sql to keep that file a manageable size.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(22);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '3a3a0000-0000-0000-0000-000000000001'
\set category2ID '3a3a0000-0000-0000-0000-000000000002'
\set community1ID '3a3a0000-0000-0000-0000-000000000003'
\set event1ID '3a3a0000-0000-0000-0000-000000000004'
\set event1PriceWindowID '3a3a0000-0000-0000-0000-000000000020'
\set event1TicketTypeID '3a3a0000-0000-0000-0000-000000000021'
\set event8ID '3a3a0000-0000-0000-0000-000000000005'
\set event8PriceWindowID '3a3a0000-0000-0000-0000-000000000022'
\set event8TicketTypeID '3a3a0000-0000-0000-0000-000000000023'
\set event9ID '3a3a0000-0000-0000-0000-000000000006'
\set event9PriceWindowID '3a3a0000-0000-0000-0000-000000000024'
\set event9TicketTypeID '3a3a0000-0000-0000-0000-000000000025'
\set event14ID '3a3a0000-0000-0000-0000-000000000007'
\set event14PriceWindowID '3a3a0000-0000-0000-0000-000000000026'
\set event14TicketTypeID '3a3a0000-0000-0000-0000-000000000027'
\set eventClearDatesID '3a3a0000-0000-0000-0000-000000000017'
\set eventClearDatesPriceWindowID '3a3a0000-0000-0000-0000-000000000028'
\set eventClearDatesTicketTypeID '3a3a0000-0000-0000-0000-000000000029'
\set eventLiveMovedID '3a3a0000-0000-0000-0000-000000000018'
\set eventLiveMovedPriceWindowID '3a3a0000-0000-0000-0000-00000000002a'
\set eventLiveMovedTicketTypeID '3a3a0000-0000-0000-0000-00000000002b'
\set eventLiveSessionID '3a3a0000-0000-0000-0000-000000000015'
\set eventLiveSessionPriceWindowID '3a3a0000-0000-0000-0000-00000000002c'
\set eventLiveSessionTicketTypeID '3a3a0000-0000-0000-0000-00000000002d'
\set eventSessionNoEndID '3a3a0000-0000-0000-0000-000000000019'
\set eventSessionNoEndPriceWindowID '3a3a0000-0000-0000-0000-00000000002e'
\set eventSessionNoEndTicketTypeID '3a3a0000-0000-0000-0000-00000000002f'
\set eventShrinkBoundsID '3a3a0000-0000-0000-0000-000000000008'
\set eventShrinkBoundsPriceWindowID '3a3a0000-0000-0000-0000-000000000030'
\set eventShrinkBoundsTicketTypeID '3a3a0000-0000-0000-0000-000000000031'
\set group1ID '3a3a0000-0000-0000-0000-000000000009'
\set groupCategoryID '3a3a0000-0000-0000-0000-000000000016'
\set session3ID '3a3a0000-0000-0000-0000-000000000010'
\set sessionShrinkBoundsID '3a3a0000-0000-0000-0000-000000000011'
\set sponsorOrigID '3a3a0000-0000-0000-0000-000000000012'
\set user1ID '3a3a0000-0000-0000-0000-000000000013'
\set user3ID '3a3a0000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'community1ID');
select fx_group_category(:'groupCategoryID', :'community1ID');
select fx_event_category(:'category1ID', :'community1ID');
select fx_event_category(:'category2ID', :'community1ID');
select fx_user(:'user1ID');
select fx_user(:'user3ID');
select fx_group(:'group1ID', :'community1ID', :'groupCategoryID');

-- Group Sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values (:'sponsorOrigID', :'group1ID', 'Original Sponsor', 'https://example.com/sponsor.png', null);

-- Event
select fx_event(:'event1ID', :'group1ID', :'category1ID', jsonb_build_object('timezone', 'America/New_York'));

-- Dated event whose dates are cleared
select fx_event(:'eventClearDatesID', :'group1ID', :'category1ID', jsonb_build_object(
    'ends_at', '2030-03-01 12:00:00+00',
    'starts_at', '2030-03-01 10:00:00+00'
));

-- Undated event given a session without an end date
select fx_event(:'eventSessionNoEndID', :'group1ID', :'category1ID');

-- Published event used for attendee floor validation checks
select fx_event(:'event14ID', :'group1ID', :'category1ID', jsonb_build_object(
    'published', true,
    'starts_at', '2030-02-10 10:00:00-05',
    'timezone', 'America/New_York'
));

-- Past Event (for testing past updates)
select fx_event(:'event8ID', :'group1ID', :'category1ID', jsonb_build_object(
    'ends_at', '2020-01-01 12:00:00-05',
    'name', 'Past Event',
    'photos_urls', array['https://example.com/original-photo.jpg'],
    'starts_at', '2020-01-01 10:00:00-05',
    'tags', array['original', 'tags'],
    'timezone', 'America/New_York',
    'venue_name', 'Original Venue'
));

-- Live Event (started in the past, ends in the future)
select fx_event(:'event9ID', :'group1ID', :'category1ID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 hours',
    'name', 'Live Event',
    'starts_at', current_timestamp - interval '1 hour'
));

-- Live event whose start date is moved later
select fx_event(:'eventLiveMovedID', :'group1ID', :'category1ID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 hours',
    'name', 'Live Moved Event',
    'starts_at', current_timestamp - interval '1 hour'
));

-- Live event dedicated to the completed-session override scenario
select fx_event(:'eventLiveSessionID', :'group1ID', :'category1ID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 hours',
    'starts_at', current_timestamp - interval '1 hour'
));

-- Completed session retained for the recording override scenario
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_provider_id,
    meeting_requested
) values (
    :'session3ID',
    :'eventLiveSessionID',
    'Completed Live Event Session',
    current_timestamp - interval '45 minutes',
    current_timestamp - interval '15 minutes',
    'virtual',
    'zoom',
    true
);

-- Event with session for bounds shrink checks
select fx_event(:'eventShrinkBoundsID', :'group1ID', :'category1ID', jsonb_build_object(
    'ends_at', '2030-05-01 17:00:00+00',
    'event_kind_id', 'virtual',
    'name', 'Shrink Bounds Event',
    'starts_at', '2030-05-01 09:00:00+00'
));

-- Session near the end of the event for bounds shrink checks
insert into session (
    session_id,
    event_id,
    name,
    description,
    starts_at,
    ends_at,
    session_kind_id
) values (
    :'sessionShrinkBoundsID',
    :'eventShrinkBoundsID',
    'Shrink Bounds Session',
    'Session near the end of the event',
    '2030-05-01 15:00:00+00',
    '2030-05-01 16:00:00+00',
    'virtual'
);

-- Free ticket tier for the base event
select fx_event_ticket_type(:'event1TicketTypeID', :'event1ID', jsonb_build_object('seats_total', 100));

-- Free ticket tier for the past event
select fx_event_ticket_type(:'event8TicketTypeID', :'event8ID', jsonb_build_object('seats_total', 100));

-- Free ticket tier for the live event
select fx_event_ticket_type(:'event9TicketTypeID', :'event9ID', jsonb_build_object('seats_total', 100));

-- Free ticket tier for the attendee floor event
select fx_event_ticket_type(:'event14TicketTypeID', :'event14ID', jsonb_build_object('seats_total', 3));

-- Free ticket tier for the cleared dates event
select fx_event_ticket_type(:'eventClearDatesTicketTypeID', :'eventClearDatesID', jsonb_build_object('seats_total', 100));

-- Free ticket tier for the live moved event
select fx_event_ticket_type(:'eventLiveMovedTicketTypeID', :'eventLiveMovedID', jsonb_build_object('seats_total', 100));

-- Free ticket tier for the live session event
select fx_event_ticket_type(:'eventLiveSessionTicketTypeID', :'eventLiveSessionID', jsonb_build_object('seats_total', 100));

-- Free ticket tier for the session without end event
select fx_event_ticket_type(:'eventSessionNoEndTicketTypeID', :'eventSessionNoEndID', jsonb_build_object('seats_total', 100));

-- Free ticket tier for the bounds shrink event
select fx_event_ticket_type(:'eventShrinkBoundsTicketTypeID', :'eventShrinkBoundsID', jsonb_build_object('seats_total', 100));

-- Current free price for the base event tier
select fx_event_ticket_price_window(:'event1PriceWindowID', :'event1TicketTypeID');

-- Current free price for the past event tier
select fx_event_ticket_price_window(:'event8PriceWindowID', :'event8TicketTypeID');

-- Current free price for the live event tier
select fx_event_ticket_price_window(:'event9PriceWindowID', :'event9TicketTypeID');

-- Current free price for the attendee floor event tier
select fx_event_ticket_price_window(:'event14PriceWindowID', :'event14TicketTypeID');

-- Current free price for the cleared dates event tier
select fx_event_ticket_price_window(:'eventClearDatesPriceWindowID', :'eventClearDatesTicketTypeID');

-- Current free price for the live moved event tier
select fx_event_ticket_price_window(:'eventLiveMovedPriceWindowID', :'eventLiveMovedTicketTypeID');

-- Current free price for the live session event tier
select fx_event_ticket_price_window(:'eventLiveSessionPriceWindowID', :'eventLiveSessionTicketTypeID');

-- Current free price for the session without end event tier
select fx_event_ticket_price_window(:'eventSessionNoEndPriceWindowID', :'eventSessionNoEndTicketTypeID');

-- Current free price for the bounds shrink event tier
select fx_event_ticket_price_window(:'eventShrinkBoundsPriceWindowID', :'eventShrinkBoundsTicketTypeID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed with event ends_at null when starts_at is null
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventClearDatesID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Test',
            'kind_id', 'in-person',
            'name', 'No Dates Event',
            'timezone', 'UTC'
        )
    ),
    'Should succeed with event ends_at null when starts_at is null'
);

-- Should clear both event dates
select results_eq(
    format(
        $$select starts_at, ends_at from event where event_id = %L::uuid$$,
        :'eventClearDatesID'
    ),
    $$values (null::timestamptz, null::timestamptz)$$,
    'Should clear both event dates'
);

-- Should reject clearing the start date on a published event
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event14ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Test',
            'kind_id', 'in-person',
            'name', 'Published No Dates Event',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'published event must have a start date',
    'Should reject clearing the start date on a published event'
);

-- Should succeed with session ends_at null when starts_at is set
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventSessionNoEndID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Test',
            'kind_id', 'in-person',
            'name', 'Session No End',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'kind', 'in-person',
                    'name', 'No End Session',
                    'starts_at', '2030-01-01T10:00:00'
                )
            ),
            'starts_at', '2030-01-01T10:00:00',
            'timezone', 'UTC'
        )
    ),
    'Should succeed with session ends_at null when starts_at is set'
);

-- Should store the session without an end date
select results_eq(
    format(
        $$
        select e.starts_at, e.ends_at, s.name, s.starts_at, s.ends_at
        from event e
        join session s using (event_id)
        where e.event_id = %L::uuid
        $$,
        :'eventSessionNoEndID'
    ),
    $$
    values (
        '2030-01-01 10:00:00+00'::timestamptz,
        null::timestamptz,
        'No End Session'::text,
        '2030-01-01 10:00:00+00'::timestamptz,
        null::timestamptz
    )
    $$,
    'Should store the session without an end date'
);

-- Should succeed with valid future dates for event and sessions
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event1ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Test',
            'ends_at', '2030-01-01T12:00:00',
            'kind_id', 'in-person',
            'name', 'Future Event',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'ends_at', '2030-01-01T11:00:00',
                    'kind', 'in-person',
                    'name', 'Future Session',
                    'starts_at', '2030-01-01T10:00:00'
                )
            ),
            'starts_at', '2030-01-01T10:00:00',
            'timezone', 'UTC'
        )
    ),
    'Should succeed with valid future dates for event and sessions'
);

-- Should store the valid future dates for event and sessions
select results_eq(
    format(
        $$
        select e.starts_at, e.ends_at, s.name, s.starts_at, s.ends_at
        from event e
        join session s using (event_id)
        where e.event_id = %L::uuid
        $$,
        :'event1ID'
    ),
    $$
    values (
        '2030-01-01 10:00:00+00'::timestamptz,
        '2030-01-01 12:00:00+00'::timestamptz,
        'Future Session'::text,
        '2030-01-01 10:00:00+00'::timestamptz,
        '2030-01-01 11:00:00+00'::timestamptz
    )
    $$,
    'Should store the valid future dates for event and sessions'
);

-- Should throw error when shrinking event bounds leaves a retained session out
-- of bounds (relies on the event row update running before the session sync)
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventShrinkBoundsID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Test',
            'ends_at', '2030-05-01T12:00:00',
            'kind_id', 'virtual',
            'name', 'Shrink Bounds Event',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'ends_at', '2030-05-01T16:00:00',
                    'kind', 'virtual',
                    'name', 'Shrink Bounds Session',
                    'session_id', :'sessionShrinkBoundsID',
                    'starts_at', '2030-05-01T15:00:00'
                )
            ),
            'starts_at', '2030-05-01T09:00:00',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'session starts_at must be within event bounds',
    'Should throw error when shrinking event bounds leaves a retained session out of bounds'
);

-- Should succeed when shrinking event bounds keeps the retained session within bounds
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventShrinkBoundsID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Test',
            'ends_at', '2030-05-01T16:30:00',
            'kind_id', 'virtual',
            'name', 'Shrink Bounds Event',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'ends_at', '2030-05-01T16:00:00',
                    'kind', 'virtual',
                    'name', 'Shrink Bounds Session',
                    'session_id', :'sessionShrinkBoundsID',
                    'starts_at', '2030-05-01T15:00:00'
                )
            ),
            'starts_at', '2030-05-01T09:00:00',
            'timezone', 'UTC'
        )
    ),
    'Should succeed when shrinking event bounds keeps the retained session within bounds'
);

-- Should store the shrunk event bounds with the retained session
select results_eq(
    format(
        $$
        select e.starts_at, e.ends_at, s.session_id, s.starts_at, s.ends_at
        from event e
        join session s using (event_id)
        where e.event_id = %L::uuid
        $$,
        :'eventShrinkBoundsID'
    ),
    format(
        $$
        values (
            '2030-05-01 09:00:00+00'::timestamptz,
            '2030-05-01 16:30:00+00'::timestamptz,
            %L::uuid,
            '2030-05-01 15:00:00+00'::timestamptz,
            '2030-05-01 16:00:00+00'::timestamptz
        )
        $$,
        :'sessionShrinkBoundsID'
    ),
    'Should store the shrunk event bounds with the retained session'
);

-- Should update all fields on past events
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event8ID',
        jsonb_build_object(
            'banner_mobile_url', 'https://example.com/banner-mobile.jpg',
            'banner_url', 'https://example.com/banner.jpg',
            'capacity', 150,
            'category_id', :'category2ID',
            'description', 'Updated description for past event',
            'description_short', 'Updated short description',
            'ends_at', '2020-01-02T12:30:00',
            'hosts', jsonb_build_array(:'user1ID'),
            'kind_id', 'virtual',
            'logo_url', 'https://example.com/logo.png',
            'luma_url', 'https://luma.com/group/events/123456',
            'meeting_join_url', 'https://meet.example.com/room',
            'meeting_provider_id', 'zoom',
            'meeting_recording_url', 'https://youtube.com/recording',
            'meeting_requested', false,
            'meetup_url', 'https://meetup.com/group/events/123456',
            'name', 'Past Event Updated',
            'photos_urls', jsonb_build_array(
                'https://example.com/photo1.jpg',
                'https://example.com/photo2.jpg'
            ),
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'ends_at', '2020-01-02T11:30:00',
                    'kind', 'virtual',
                    'meeting_join_instructions', 'Past session instructions',
                    'name', 'Past Session',
                    'starts_at', '2020-01-02T10:30:00'
                )
            ),
            'speakers', jsonb_build_array(
                jsonb_build_object(
                    'featured', true,
                    'user_id', :'user3ID'
                )
            ),
            'sponsors', jsonb_build_array(
                jsonb_build_object(
                    'group_sponsor_id', :'sponsorOrigID',
                    'level', 'Gold'
                )
            ),
            'starts_at', '2020-01-02T10:00:00',
            'tags', jsonb_build_array('updated', 'past', 'event'),
            'timezone', 'UTC',
            'venue_address', '123 Updated St',
            'venue_city', 'Updated City',
            'venue_country_code', 'US',
            'venue_country_name', 'United States',
            'venue_name', 'Updated Venue',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '12345'
        )
    ),
    'Should update all fields on past events'
);

-- Verify past event fields were updated
select is(
    (
        select jsonb_build_object(
            'banner_mobile_url', banner_mobile_url,
            'banner_url', banner_url,
            'capacity', capacity,
            'description', description,
            'description_short', description_short,
            'ends_at', ends_at,
            'event_category_id', event_category_id,
            'event_kind_id', event_kind_id,
            'logo_url', logo_url,
            'luma_url', luma_url,
            'meeting_join_url', meeting_join_url,
            'meeting_provider_id', meeting_provider_id,
            'meeting_recording_url', meeting_recording_url,
            'meeting_requested', meeting_requested,
            'meetup_url', meetup_url,
            'name', name,
            'photos_urls', photos_urls,
            'starts_at', starts_at,
            'tags', tags,
            'timezone', timezone,
            'venue_address', venue_address,
            'venue_city', venue_city,
            'venue_country_code', venue_country_code,
            'venue_country_name', venue_country_name,
            'venue_name', venue_name,
            'venue_state_code', venue_state_code,
            'venue_state_name', venue_state_name,
            'venue_zip_code', venue_zip_code
        )
        from event
        where event_id = :'event8ID'::uuid
    ),
    jsonb_build_object(
        'banner_mobile_url', 'https://example.com/banner-mobile.jpg',
        'banner_url', 'https://example.com/banner.jpg',
        'capacity', 100,
        'description', 'Updated description for past event',
        'description_short', 'Updated short description',
        'ends_at', '2020-01-02 12:30:00+00'::timestamptz,
        'event_category_id', :'category2ID'::uuid,
        'event_kind_id', 'virtual',
        'logo_url', 'https://example.com/logo.png',
        'luma_url', 'https://luma.com/group/events/123456',
        'meeting_join_url', 'https://meet.example.com/room',
        'meeting_provider_id', 'zoom',
        'meeting_recording_url', 'https://youtube.com/recording',
        'meeting_requested', false,
        'meetup_url', 'https://meetup.com/group/events/123456',
        'name', 'Past Event Updated',
        'photos_urls', array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
        'starts_at', '2020-01-02 10:00:00+00'::timestamptz,
        'tags', array['updated', 'past', 'event'],
        'timezone', 'UTC',
        'venue_address', '123 Updated St',
        'venue_city', 'Updated City',
        'venue_country_code', 'US',
        'venue_country_name', 'United States',
        'venue_name', 'Updated Venue',
        'venue_state_code', 'CA',
        'venue_state_name', 'California',
        'venue_zip_code', '12345'
    ),
    'Should update past event fields'
);

-- Should update hosts on past events
select is(
    (
        select array_agg(user_id order by user_id)
        from event_host
        where event_id = :'event8ID'::uuid
    ),
    array[:'user1ID']::uuid[],
    'Should update hosts on past events'
);

-- Should update speakers on past events
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'featured', featured,
                'user_id', user_id
            )
            order by user_id
        )
        from event_speaker
        where event_id = :'event8ID'::uuid
    ),
    jsonb_build_array(
        jsonb_build_object(
            'featured', true,
            'user_id', :'user3ID'
        )
    ),
    'Should update speakers on past events'
);

-- Should update sponsors on past events
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'group_sponsor_id', group_sponsor_id,
                'level', level
            )
            order by group_sponsor_id
        )
        from event_sponsor
        where event_id = :'event8ID'::uuid
    ),
    jsonb_build_array(
        jsonb_build_object(
            'group_sponsor_id', :'sponsorOrigID',
            'level', 'Gold'
        )
    ),
    'Should update sponsors on past events'
);

-- Should update sessions on past events
select is(
    (
        select jsonb_build_object(
            'ends_at', ends_at,
            'meeting_join_instructions', meeting_join_instructions,
            'name', name,
            'session_kind_id', session_kind_id,
            'starts_at', starts_at
        )
        from session
        where event_id = :'event8ID'::uuid
        limit 1
    ),
    jsonb_build_object(
        'ends_at', '2020-01-02 11:30:00+00'::timestamptz,
        'meeting_join_instructions', 'Past session instructions',
        'name', 'Past Session',
        'session_kind_id', 'virtual',
        'starts_at', '2020-01-02 10:30:00+00'::timestamptz
    ),
    'Should update sessions on past events'
);

-- Should succeed updating live event when starts_at is unchanged
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event9ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Updated description',
            'ends_at', to_char(
                (select ends_at from event where event_id = :'event9ID'::uuid) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'kind_id', 'in-person',
            'name', 'Live Event Updated',
            'starts_at', to_char(
                (select starts_at from event where event_id = :'event9ID'::uuid) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'timezone', 'UTC'
        )
    ),
    'Should succeed updating live event when starts_at is unchanged'
);

-- Should keep the live event start date while updating its name
select results_eq(
    format(
        $$select name, starts_at from event where event_id = %L::uuid$$,
        :'event9ID'
    ),
    $$values ('Live Event Updated'::text, date_trunc('second', current_timestamp - interval '1 hour'))$$,
    'Should keep the live event start date while updating its name'
);

-- Should succeed updating live event when starts_at is moved later (but still in past)
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventLiveMovedID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Updated description again',
            'ends_at', to_char(
                (select ends_at from event where event_id = :'eventLiveMovedID'::uuid) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'kind_id', 'in-person',
            'name', 'Live Event Updated Again',
            'starts_at', to_char(
                (select starts_at from event where event_id = :'eventLiveMovedID'::uuid) at time zone 'UTC'
                    + interval '30 minutes',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'timezone', 'UTC'
        )
    ),
    'Should succeed updating live event when starts_at is moved later (but still in past)'
);

-- Should store the live event start date moved later
select is(
    (select starts_at from event where event_id = :'eventLiveMovedID'::uuid),
    date_trunc('second', current_timestamp - interval '1 hour') + interval '30 minutes',
    'Should store the live event start date moved later'
);

-- Should update session recording override when the live event has a completed session
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventLiveSessionID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Updated description with completed session override',
            'ends_at', to_char(
                (select ends_at from event where event_id = :'eventLiveSessionID'::uuid) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'kind_id', 'in-person',
            'name', 'Live Event Updated With Session Override',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'ends_at', to_char(
                        (select ends_at from session where session_id = :'session3ID'::uuid) at time zone 'UTC',
                        'YYYY-MM-DD"T"HH24:MI:SS'
                    ),
                    'kind', 'virtual',
                    'meeting_provider_id', 'zoom',
                    'meeting_recording_url', 'https://youtube.com/watch?v=live-session-override',
                    'meeting_requested', true,
                    'name', 'Completed Live Event Session',
                    'session_id', :'session3ID',
                    'starts_at', to_char(
                        (select starts_at from session where session_id = :'session3ID'::uuid) at time zone 'UTC',
                        'YYYY-MM-DD"T"HH24:MI:SS'
                    )
                )
            ),
            'starts_at', to_char(
                (select starts_at from event where event_id = :'eventLiveSessionID'::uuid) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'timezone', 'UTC'
        )
    ),
    'Should update session recording override when the live event has a completed session'
);

-- Should persist the completed session recording override on a live event update
select is(
    (select meeting_recording_url from session where session_id = :'session3ID'::uuid),
    'https://youtube.com/watch?v=live-session-override',
    'Should persist the completed session recording override on a live event update'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
