-- Tests listing a user's current and upcoming attendee check-in events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set admissionOfferID '3a2d0000-0000-0000-0000-000000000014'
\set canceledEventID '3a2d0000-0000-0000-0000-000000000010'
\set communityID '3a2d0000-0000-0000-0000-000000000001'
\set currentEventID '3a2d0000-0000-0000-0000-000000000002'
\set endedEventID '3a2d0000-0000-0000-0000-000000000009'
\set eventCategoryID '3a2d0000-0000-0000-0000-000000000003'
\set futureEventID '3a2d0000-0000-0000-0000-000000000004'
\set groupCategoryID '3a2d0000-0000-0000-0000-000000000005'
\set groupID '3a2d0000-0000-0000-0000-000000000006'
\set nonConfirmedEventID '3a2d0000-0000-0000-0000-000000000013'
\set otherUserID '3a2d0000-0000-0000-0000-000000000007'
\set ticketTypeID '3a2d0000-0000-0000-0000-000000000015'
\set unpublishedEventID '3a2d0000-0000-0000-0000-000000000011'
\set unscheduledEventID '3a2d0000-0000-0000-0000-000000000012'
\set userID '3a2d0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the attendee events
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'A test community',
    'Test Community',
    'https://example.com/logo.png',
    'test-community'
);

-- Group category used by the attendee group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category used by attendee events
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Attendee and unrelated user identities
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'otherUserID', 'hash-1', 'other@example.com', true, 'other'),
    (:'userID', 'hash-2', 'attendee@example.com', true, 'attendee');

-- Group owning the attendee events
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Current, future, and explicitly ended events used by attendee ordering scenarios
insert into event (
    event_id,
    description,
    ends_at,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    published_at,
    slug,
    starts_at,
    timezone
) values
    (
        :'currentEventID',
        'A current event',
        current_timestamp + interval '1 hour',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Current Event',
        true,
        current_timestamp - interval '2 hours',
        'current-event',
        current_timestamp - interval '1 hour',
        'UTC'
    ),
    (
        :'endedEventID',
        'An event that ended earlier on its local day',
        date_trunc('day', current_timestamp at time zone 'UTC') at time zone 'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Ended Event',
        true,
        current_timestamp - interval '1 day',
        'ended-event',
        (
            date_trunc('day', current_timestamp at time zone 'UTC') - interval '1 hour'
        ) at time zone 'UTC',
        'UTC'
    ),
    (
        :'futureEventID',
        'A future event',
        null,
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Future Event',
        true,
        current_timestamp,
        'future-event',
        current_timestamp + interval '1 day',
        'UTC'
    );

-- Ticket type used by the completed admission offer fallback
insert into event_ticket_type (event_id, event_ticket_type_id, "order", seats_total, title)
values (:'futureEventID', :'ticketTypeID', 1, 10, 'Ticket type fallback');

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

-- Events used by attendee and event visibility exclusions
insert into event (
    event_id,
    canceled,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    published_at,
    slug,
    starts_at,
    timezone
) values
    (
        :'canceledEventID',
        true,
        'A canceled event',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Canceled Event',
        true,
        current_timestamp,
        'canceled-event',
        current_timestamp + interval '2 days',
        'UTC'
    ),
    (
        :'nonConfirmedEventID',
        false,
        'An event with non-confirmed attendance',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Non-confirmed Event',
        true,
        current_timestamp,
        'non-confirmed-event',
        current_timestamp + interval '2 days',
        'UTC'
    ),
    (
        :'unpublishedEventID',
        false,
        'An unpublished event',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Unpublished Event',
        false,
        null,
        'unpublished-event',
        current_timestamp + interval '2 days',
        'UTC'
    ),
    (
        :'unscheduledEventID',
        false,
        'An unscheduled event',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Unscheduled Event',
        true,
        current_timestamp,
        'unscheduled-event',
        null,
        'UTC'
    );

-- Confirmed attendee rows for current and future events
insert into event_attendee (event_id, user_id, checked_in, status) values
    (:'canceledEventID', :'userID', false, 'confirmed'),
    (:'currentEventID', :'userID', true, 'confirmed'),
    (:'endedEventID', :'userID', false, 'confirmed'),
    (:'futureEventID', :'userID', false, 'confirmed'),
    (:'nonConfirmedEventID', :'userID', false, 'attendance-canceled'),
    (:'unpublishedEventID', :'userID', false, 'confirmed'),
    (:'unscheduledEventID', :'userID', false, 'confirmed');

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
