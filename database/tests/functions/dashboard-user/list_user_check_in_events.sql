-- Tests listing a user's current and upcoming attendee check-in events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set admissionOfferID '4a000000-0000-0000-0000-000000000014'
\set communityID '4a000000-0000-0000-0000-000000000001'
\set currentEventID '4a000000-0000-0000-0000-000000000002'
\set endedEventID '4a000000-0000-0000-0000-000000000009'
\set eventCategoryID '4a000000-0000-0000-0000-000000000003'
\set futureEventID '4a000000-0000-0000-0000-000000000004'
\set groupCategoryID '4a000000-0000-0000-0000-000000000005'
\set groupID '4a000000-0000-0000-0000-000000000006'
\set nonConfirmedEventID '4a000000-0000-0000-0000-000000000013'
\set otherUserID '4a000000-0000-0000-0000-000000000007'
\set ticketTypeID '4a000000-0000-0000-0000-000000000015'
\set userID '4a000000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the group
select fx_community(:'communityID');

-- User whose attendance is excluded from the listed user's events
select fx_user(:'otherUserID');

-- User whose check-in events are listed
select fx_user(:'userID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Current, future, and explicitly ended events used by attendee ordering scenarios
select fx_event(:'currentEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 hour',
    'published', true,
    'published_at', current_timestamp - interval '2 hours',
    'starts_at', current_timestamp - interval '1 hour'
));
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', date_trunc('day', current_timestamp at time zone 'UTC') at time zone 'UTC',
    'published', true,
    'published_at', current_timestamp - interval '1 day',
    'starts_at', (
            date_trunc('day', current_timestamp at time zone 'UTC') - interval '1 hour'
        ) at time zone 'UTC'
));
select fx_event(:'futureEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '1 day'
));

-- Event used by the non-confirmed attendance exclusion
select fx_event(:'nonConfirmedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '2 days'
));

-- Ticket type used by the completed admission offer fallback
select fx_event_ticket_type(:'ticketTypeID', :'futureEventID', jsonb_build_object('seats_total', 10));

-- Completed admission offer used by the ticket-title fallback
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id,

    amount_minor,
    discount_amount_minor,
    ticket_title
) values (
    :'admissionOfferID',
    :'futureEventID',
    :'ticketTypeID',
    current_timestamp + interval '3 days',
    'approval',
    'completed',
    :'userID',

    0,
    0,
    'Offer admission'
);

-- Attendee rows for current, future, closed-window and non-confirmed scenarios
insert into event_attendee (
    event_id,
    user_id,
    checked_in,
    status,

    attendance_canceled_at
) values
    (:'currentEventID', :'userID', true, 'confirmed', null),
    (:'endedEventID', :'userID', false, 'confirmed', null),
    (:'futureEventID', :'userID', false, 'confirmed', null),
    (:'nonConfirmedEventID', :'userID', false, 'attendance-canceled', current_timestamp);

-- Unrelated attendance excluded from the user's list
insert into event_attendee (event_id, user_id, status)
values (:'futureEventID', :'otherUserID', 'confirmed');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list the user's in-progress event before the upcoming event
select results_eq(
    format(
        $$
            select value->>'event_id'
            from json_array_elements(list_user_check_in_events(%L::uuid)) value
        $$,
        :'userID'
    ),
    format(
        $$ values (%L::text), (%L::text) $$,
        :'currentEventID',
        :'futureEventID'
    ),
    'Should list the user''s in-progress event before the upcoming event'
);

-- Should retain checked-in events with their status
select is(
    (
        select (value->>'checked_in')::boolean
        from json_array_elements(list_user_check_in_events(:'userID'::uuid)) value
        where value->>'event_id' = :'currentEventID'
    ),
    true,
    'Should retain checked-in events with their status'
);

-- Should fall back to a completed admission-offer ticket snapshot
select is(
    (
        select value->>'ticket_title'
        from json_array_elements(list_user_check_in_events(:'userID'::uuid)) value
        where value->>'event_id' = :'futureEventID'
    ),
    'Offer admission',
    'Should fall back to a completed admission-offer ticket snapshot'
);

-- Should never expose the raw credential in listing payloads
select ok(
    not list_user_check_in_events(:'userID'::uuid)::text like '%check_in_code%',
    'Should never expose the raw credential in listing payloads'
);

-- Should return the exact attendee card contract
select results_eq(
    format(
        $$
            select key
            from json_each((list_user_check_in_events(%L::uuid)->0))
            order by key
        $$,
        :'userID'
    ),
    $$
        values
            ('checked_in'),
            ('cohosts'),
            ('event_id'),
            ('in_progress'),
            ('kind'),
            ('location'),
            ('logo_url'),
            ('name'),
            ('starts_at'),
            ('ticket_title'),
            ('timezone')
    $$,
    'Should return the exact attendee card contract'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
