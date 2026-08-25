-- Tests resolving attendee credentials through the organizer scanner flow.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set admissionOfferID '3a2b0000-0000-0000-0000-000000000012'
\set actorUserID '3a2b0000-0000-0000-0000-000000000001'
\set attendeeUserID '3a2b0000-0000-0000-0000-000000000002'
\set canceledAttendeeUserID '3a2b0000-0000-0000-0000-000000000014'
\set canceledCheckInCode '3a2b0000-0000-0000-0000-000000000015'
\set checkInCode '3a2b0000-0000-0000-0000-000000000003'
\set communityID '3a2b0000-0000-0000-0000-000000000004'
\set endedCheckInCode '3a2b0000-0000-0000-0000-000000000010'
\set endedEventID '3a2b0000-0000-0000-0000-000000000011'
\set eventCategoryID '3a2b0000-0000-0000-0000-000000000005'
\set eventID '3a2b0000-0000-0000-0000-000000000006'
\set groupCategoryID '3a2b0000-0000-0000-0000-000000000007'
\set groupID '3a2b0000-0000-0000-0000-000000000008'
\set ticketTypeID '3a2b0000-0000-0000-0000-000000000013'
\set unknownCode '3a2b0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the scanned event
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

-- Group category used by the scanner group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category used by the scanned event
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Organizer and attendee identities used by scanner scenarios
insert into "user" (user_id, auth_hash, email, email_verified, name, photo_url, username) values
    (:'actorUserID', 'hash-1', 'actor@example.com', true, 'Actor User', null, 'actor'),
    (
        :'canceledAttendeeUserID',
        'hash-3',
        'canceled@example.com',
        true,
        'Canceled Attendee',
        null,
        'canceled-attendee'
    ),
    (
        :'attendeeUserID',
        'hash-2',
        'attendee@example.com',
        true,
        'Attendee User',
        'https://example.com/attendee.png',
        'attendee'
    );

-- Group owning the scanned event
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Published events used by available and explicitly ended scan scenarios
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
        :'eventID',
        'An event for scanner tests',
        null,
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Scanner Event',
        true,
        current_timestamp,
        'scanner-event',
        current_timestamp + interval '3 hours',
        'UTC'
    ),
    (
        :'endedEventID',
        'An event that ended earlier on its local day',
        date_trunc('day', current_timestamp at time zone 'UTC') at time zone 'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        'Ended Scanner Event',
        true,
        current_timestamp - interval '1 day',
        'ended-scanner-event',
        (
            date_trunc('day', current_timestamp at time zone 'UTC') - interval '1 hour'
        ) at time zone 'UTC',
        'UTC'
    );

-- Ticket type used by the completed organizer offer fallback
insert into event_ticket_type (event_id, event_ticket_type_id, "order", seats_total, title)
values (:'eventID', :'ticketTypeID', 1, 10, 'Ticket type fallback');

-- Completed organizer offer providing the attendee ticket snapshot
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    organizer_user_id,
    source,
    status,
    user_id,

    amount_minor,
    discount_amount_minor,
    ticket_title
) values (
    :'admissionOfferID',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 day',
    :'actorUserID',
    'organizer_invitation',
    'completed',
    :'attendeeUserID',

    0,
    0,
    'Organizer admission'
);

-- Attendees carrying credentials for confirmed, canceled, and ended-event scenarios
insert into event_attendee (
    event_id,
    user_id,
    check_in_code,
    status,

    attendance_canceled_at
) values
    (
        :'eventID',
        :'canceledAttendeeUserID',
        :'canceledCheckInCode',
        'attendance-canceled',

        current_timestamp
    ),
    (:'endedEventID', :'actorUserID', :'endedCheckInCode', 'confirmed', null),
    (:'eventID', :'attendeeUserID', :'checkInCode', 'confirmed', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return attendee details for the first scan
select is(
    (
        check_in_attendee_by_code(
            :'actorUserID'::uuid,
            :'checkInCode'::uuid,
            :'communityID'::uuid,
            :'eventID'::uuid,
            :'groupID'::uuid
        )::jsonb - 'checked_in_at'
    ),
    jsonb_build_object(
        'attendee', jsonb_build_object(
            'username', 'attendee',

            'name', 'Attendee User',
            'photo_url', 'https://example.com/attendee.png'
        ),
        'outcome', 'checked-in',
        'ticket_title', 'Organizer admission'
    ),
    'Should return attendee details for the first scan'
);

-- Should return a durable check-in timestamp
select ok(
    (
        check_in_attendee_by_code(
            :'actorUserID'::uuid,
            :'checkInCode'::uuid,
            :'communityID'::uuid,
            :'eventID'::uuid,
            :'groupID'::uuid
        )::jsonb->>'checked_in_at'
    )::bigint > 0,
    'Should return a durable check-in timestamp'
);

-- Should return the neutral outcome for a duplicate scan
select is(
    check_in_attendee_by_code(
        :'actorUserID'::uuid,
        :'checkInCode'::uuid,
        :'communityID'::uuid,
        :'eventID'::uuid,
        :'groupID'::uuid
    )::jsonb->>'outcome',
    'already-checked-in',
    'Should return the neutral outcome for a duplicate scan'
);

-- Should keep one audit row across duplicate scans
select is(
    (select count(*)::int from audit_log),
    1,
    'Should keep one audit row across duplicate scans'
);

-- Should reject an unknown credential
select throws_ok(
    format(
        'select check_in_attendee_by_code(%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'unknownCode',
        :'communityID',
        :'eventID',
        :'groupID'
    ),
    'check-in credential not found',
    'Should reject an unknown credential'
);

-- Should reject a credential from the wrong selected group
select throws_ok(
    format(
        'select check_in_attendee_by_code(%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'checkInCode',
        :'communityID',
        :'eventID',
        :'unknownCode'
    ),
    'event unavailable for check-in',
    'Should reject a credential from the wrong selected group'
);

-- Should reject a credential after the event's explicit end time
select throws_ok(
    format(
        'select check_in_attendee_by_code(%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'endedCheckInCode',
        :'communityID',
        :'endedEventID',
        :'groupID'
    ),
    'event unavailable for check-in',
    'Should reject a credential after the event''s explicit end time'
);

-- Should reject a credential whose attendance is no longer confirmed
select throws_ok(
    format(
        'select check_in_attendee_by_code(%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'canceledCheckInCode',
        :'communityID',
        :'eventID',
        :'groupID'
    ),
    'attendance is not confirmed',
    'Should reject a credential whose attendance is no longer confirmed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
