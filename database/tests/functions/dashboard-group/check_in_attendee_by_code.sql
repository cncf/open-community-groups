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

-- Baseline community, categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'canceledAttendeeUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');


-- Organizer and attendee identities used by scanner scenarios
select fx_user(:'actorUserID', jsonb_build_object('username', 'actor-check-in-attendee-by-code'));

select fx_user(:'attendeeUserID', jsonb_build_object(
    'name', 'Attendee User',
    'photo_url', 'https://example.com/attendee.png',
    'username', 'attendee-check-in-attendee-by-code'
));

-- Published events used by available and explicitly ended scan scenarios
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '3 hours'
));
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', date_trunc('day', current_timestamp at time zone 'UTC') at time zone 'UTC',
    'published', true,
    'published_at', current_timestamp - interval '1 day',
    'starts_at', (
            date_trunc('day', current_timestamp at time zone 'UTC') - interval '1 hour'
        ) at time zone 'UTC'
));

-- Ticket type used by the completed organizer offer fallback
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('seats_total', 10));

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
            'username', 'attendee-check-in-attendee-by-code',

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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
    'attendance is not confirmed',
    'Should reject a credential whose attendance is no longer confirmed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
