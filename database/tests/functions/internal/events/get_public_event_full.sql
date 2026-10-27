-- Tests returning public full event information.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeOfferID '0c160000-0000-0000-0000-00000000000d'
\set activeOfferUserID '0c160000-0000-0000-0000-00000000000e'
\set activeHoldUserID '0c160000-0000-0000-0000-00000000000f'
\set communityID '0c160000-0000-0000-0000-000000000001'
\set completedPurchaseUserID '0c160000-0000-0000-0000-000000000010'
\set eventCategoryID '0c160000-0000-0000-0000-000000000002'
\set eventID '0c160000-0000-0000-0000-000000000003'
\set eventPrivateID '0c160000-0000-0000-0000-00000000000a'
\set expiredHoldUserID '0c160000-0000-0000-0000-000000000011'
\set expiredOfferID '0c160000-0000-0000-0000-000000000012'
\set expiredOfferUserID '0c160000-0000-0000-0000-000000000013'
\set futurePublicTicketTypeID '0c160000-0000-0000-0000-000000000017'
\set futurePublicWindowID '0c160000-0000-0000-0000-000000000018'
\set groupCategoryID '0c160000-0000-0000-0000-000000000004'
\set groupID '0c160000-0000-0000-0000-000000000005'
\set inactivePublicTicketTypeID '0c160000-0000-0000-0000-000000000015'
\set inactivePublicWindowID '0c160000-0000-0000-0000-000000000016'
\set manualSessionID '0c160000-0000-0000-0000-00000000001e'
\set meetingDiscountCodeID '0c160000-0000-0000-0000-00000000001c'
\set meetingEventID '0c160000-0000-0000-0000-000000000019'
\set meetingSessionID '0c160000-0000-0000-0000-00000000001d'
\set meetingTicketTypeID '0c160000-0000-0000-0000-00000000001a'
\set meetingWindowID '0c160000-0000-0000-0000-00000000001b'
\set organizerOnlyEventKeys '{discount_codes,manual_tax_rate_ids,meeting_error,meeting_hosts,meeting_in_sync,meeting_password,meeting_recording_raw_urls,meeting_recording_requested,meeting_recording_url,meeting_requested,registration_questions_locked}'
\set organizerOnlySessionKeys '{meeting_error,meeting_hosts,meeting_in_sync,meeting_password,meeting_recording_raw_urls,meeting_recording_url,meeting_requested}'
\set pendingRequestUserID '0c160000-0000-0000-0000-000000000014'
\set privateOnlyTicketTypeID '0c160000-0000-0000-0000-00000000000b'
\set privateOnlyWindowID '0c160000-0000-0000-0000-00000000000c'
\set privateTicketTypeID '0c160000-0000-0000-0000-000000000006'
\set privateWindowID '0c160000-0000-0000-0000-000000000007'
\set publicTicketTypeID '0c160000-0000-0000-0000-000000000008'
\set publicWindowID '0c160000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'activeOfferUserID');
select fx_user(:'activeHoldUserID');
select fx_user(:'completedPurchaseUserID');
select fx_user(:'expiredHoldUserID');
select fx_user(:'expiredOfferUserID');
select fx_user(:'pendingRequestUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events with mixed and fully invitation-only ticket inventory
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 65,
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true
));
select fx_event(:'eventPrivateID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 5,
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true
));

-- Paid manual-tax event with an automatic meeting and organizer sync state
select fx_event(:'meetingEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 50,
    'ends_at', '2030-05-01 12:00:00+00',
    'event_kind_id', 'virtual',
    'manual_tax_rate_ids', array['txr_0c16_manual'],
    'meeting_error', 'provider timeout',
    'meeting_hosts', array['host-0c16@example.com'],
    'meeting_in_sync', false,
    'meeting_provider_id', 'zoom',
    'meeting_recording_url', 'https://video.example.com/0c16-unpublished',
    'meeting_requested', true,
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', '2030-05-01 09:00:00+00',
    'tax_calculation_mode', 'manual'
));

-- Discount code configured by organizers on the meeting event
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    :'meetingDiscountCodeID',
    500,
    '0C16-SAVE',
    :'meetingEventID',
    'fixed_amount',
    'Organizer discount'
);

-- Public and invitation-only ticket types for each event
select fx_event_ticket_type(:'publicTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'Public pass'
));
select fx_event_ticket_type(:'privateTicketTypeID', :'eventID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 2,
    'seats_total', 5
));
select fx_event_ticket_type(:'inactivePublicTicketTypeID', :'eventID', jsonb_build_object(
    'active', false,
    'order', 3,
    'seats_total', 20
));
select fx_event_ticket_type(:'futurePublicTicketTypeID', :'eventID', jsonb_build_object(
    'order', 4,
    'seats_total', 30
));
select fx_event_ticket_type(:'privateOnlyTicketTypeID', :'eventPrivateID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 5
));
select fx_event_ticket_type(:'meetingTicketTypeID', :'meetingEventID', jsonb_build_object(
    'seats_total', 50,
    'title', 'Meeting pass'
));

-- Provider meeting with secrets linked to the meeting event
insert into meeting (
    event_id,
    join_url,
    meeting_provider_id,
    password,
    provider_meeting_id,
    recording_urls
) values (
    :'meetingEventID',
    'https://zoom.example.com/0c16-event',
    'zoom',
    'event-secret',
    '0c16-event-meeting',
    array['https://zoom.example.com/0c16-event-recording']::text[]
);

-- Automatic-meeting session with organizer sync state
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_error,
    meeting_hosts,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'meetingSessionID',
    :'meetingEventID',
    'Automatic meeting session',
    'virtual',
    '2030-05-01 09:00:00+00',
    '2030-05-01 10:00:00+00',
    'session provider timeout',
    array['session-host-0c16@example.com'],
    false,
    'zoom',
    true
);

-- Manual-meeting session with a published recording
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at,
    meeting_join_url,
    meeting_recording_published,
    meeting_recording_url,
    meeting_requested
) values (
    :'manualSessionID',
    :'meetingEventID',
    'Manual meeting session',
    'virtual',
    '2030-05-01 10:00:00+00',
    '2030-05-01 11:00:00+00',
    'https://stream.example.com/0c16-manual',
    true,
    'https://video.example.com/0c16-manual-recording',
    false
);

-- Active and expired organizer invitations for public inventory
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values
    (
        :'activeOfferID',
        current_timestamp,
        :'eventID',
        :'publicTicketTypeID',
        current_timestamp + interval '1 hour',
        'organizer_invitation',
        'pending',
        :'activeOfferUserID'
    ),
    (
        :'expiredOfferID',
        current_timestamp - interval '2 hours',
        :'eventID',
        :'publicTicketTypeID',
        current_timestamp - interval '1 hour',
        'organizer_invitation',
        'pending',
        :'expiredOfferUserID'
    );

-- Pending invitation request awaiting organizer approval
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    status,
    user_id
) values (
    :'eventID',
    :'publicTicketTypeID',
    'pending',
    :'pendingRequestUserID'
);

-- Completed purchase plus active and expired checkout holds
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values
    (
        0,
        'USD',
        :'eventID',
        :'publicTicketTypeID',
        null,
        'completed',
        'Public pass',
        :'completedPurchaseUserID'
    ),
    (
        0,
        'USD',
        :'eventID',
        :'publicTicketTypeID',
        current_timestamp + interval '1 hour',
        'pending',
        'Public pass',
        :'activeHoldUserID'
    ),
    (
        0,
        'USD',
        :'eventID',
        :'publicTicketTypeID',
        current_timestamp - interval '1 hour',
        'pending',
        'Public pass',
        :'expiredHoldUserID'
    );

-- Current and future prices for public and invitation-only ticket types of each event
select fx_event_ticket_price_window(:'futurePublicWindowID', :'futurePublicTicketTypeID', jsonb_build_object(
    'amount_minor', 2500,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event_ticket_price_window(:'inactivePublicWindowID', :'inactivePublicTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'meetingWindowID', :'meetingTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'privateOnlyWindowID', :'privateOnlyTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'privateWindowID', :'privateTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'publicWindowID', :'publicTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Provider meeting with secrets linked to the automatic-meeting session
insert into meeting (
    join_url,
    meeting_provider_id,
    password,
    provider_meeting_id,
    recording_urls,
    session_id
) values (
    'https://zoom.example.com/0c16-session',
    'zoom',
    'session-secret',
    '0c16-session-meeting',
    array['https://zoom.example.com/0c16-session-recording']::text[],
    :'meetingSessionID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should calculate capacity from visible public ticket inventory
select is(
    (
        get_public_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventID'::uuid
        )::jsonb->>'capacity'
    )::int,
    10,
    'Should calculate capacity from visible public ticket inventory'
);

-- Should calculate remaining capacity from canonical public ticket allocations
select is(
    (
        get_public_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventID'::uuid
        )::jsonb->>'remaining_capacity'
    )::int,
    7,
    'Should calculate remaining capacity from canonical public ticket allocations'
);

-- Should keep attendee-facing meeting fields
select is(
    jsonb_build_object(
        'event_meeting_join_url', public_event->'meeting_join_url',
        'session_meeting_join_url', manual_session->'meeting_join_url',
        'session_meeting_recording_public_url', manual_session->'meeting_recording_public_url'
    ),
    jsonb_build_object(
        'event_meeting_join_url', 'https://zoom.example.com/0c16-event',
        'session_meeting_join_url', 'https://stream.example.com/0c16-manual',
        'session_meeting_recording_public_url', 'https://video.example.com/0c16-manual-recording'
    ),
    'Should keep attendee-facing meeting fields'
)
from (
    select get_public_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'meetingEventID'::uuid
    )::jsonb as public_event
) public_event_projection
cross join lateral (
    select public_session.value as manual_session
    from jsonb_each(public_event->'sessions') as day(key, value)
    cross join lateral jsonb_array_elements(day.value) as public_session(value)
    where public_session.value->>'session_id' = :'manualSessionID'
) manual_session_projection;

-- Should keep organizer inventory across all ticket types unchanged
select is(
    jsonb_build_object(
        'capacity', organizer_event->'capacity',
        'remaining_capacity', organizer_event->'remaining_capacity'
    ),
    jsonb_build_object(
        'capacity', 65,
        'remaining_capacity', 62
    ),
    'Should keep organizer inventory across all ticket types unchanged'
)
from (
    select get_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid
    )::jsonb as organizer_event
) organizer_event_projection;

-- Should keep organizer-only configuration and secrets in the organizer projection
select is(
    jsonb_build_object(
        'missing_event_keys', (
            select coalesce(jsonb_agg(event_key order by event_key), '[]'::jsonb)
            from unnest(:'organizerOnlyEventKeys'::text[]) as event_key
            where not (organizer_event ? event_key)
        ),
        'missing_session_keys', (
            -- Require each session key on at least one organizer session
            select coalesce(jsonb_agg(session_key order by session_key), '[]'::jsonb)
            from unnest(:'organizerOnlySessionKeys'::text[]) as session_key
            where not exists (
                select 1
                from jsonb_each(organizer_event->'sessions') as day(key, value)
                cross join lateral jsonb_array_elements(day.value) as organizer_session(value)
                where organizer_session.value ? session_key
            )
        )
    ),
    jsonb_build_object(
        'missing_event_keys', '[]'::jsonb,
        'missing_session_keys', '[]'::jsonb
    ),
    'Should keep organizer-only configuration and secrets in the organizer projection'
)
from (
    select get_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'meetingEventID'::uuid
    )::jsonb as organizer_event
) organizer_event_projection;

-- Should omit organizer-only configuration and secrets
select is(
    jsonb_build_object(
        'leaked_event_keys', (
            select coalesce(jsonb_agg(event_key order by event_key), '[]'::jsonb)
            from unnest(:'organizerOnlyEventKeys'::text[]) as event_key
            where public_event ? event_key
        ),
        'leaked_session_keys', (
            select coalesce(jsonb_agg(distinct session_key order by session_key), '[]'::jsonb)
            from jsonb_each(public_event->'sessions') as day(key, value)
            cross join lateral jsonb_array_elements(day.value) as public_session(value)
            cross join unnest(:'organizerOnlySessionKeys'::text[]) as session_key
            where public_session.value ? session_key
        ),
        'session_count', (
            -- Count every session so an empty projection cannot pass
            select count(*)
            from jsonb_each(public_event->'sessions') as day(key, value)
            cross join lateral jsonb_array_elements(day.value) as public_session(value)
        )
    ),
    jsonb_build_object(
        'leaked_event_keys', '[]'::jsonb,
        'leaked_session_keys', '[]'::jsonb,
        'session_count', 2
    ),
    'Should omit organizer-only configuration and secrets'
)
from (
    select get_public_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'meetingEventID'::uuid
    )::jsonb as public_event
) public_event_projection;

-- Should omit public inventory for fully invitation-only events
select ok(
    not (private_event ? 'capacity')
    and not (private_event ? 'remaining_capacity')
    and not (private_event ? 'ticket_types'),
    'Should omit public inventory for fully invitation-only events'
)
from (
    select get_public_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventPrivateID'::uuid
    )::jsonb as private_event
) private_event_projection;

-- Should remove the superseded ticketed enrollment flag
select ok(
    not (
        get_public_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventPrivateID'::uuid
        )::jsonb ? 'is_ticketed'
    ),
    'Should remove the superseded ticketed enrollment flag'
);

-- Should replace organizer ticket inventory with the public projection
select is(
    (get_public_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid
    )::jsonb)->'ticket_types',
    list_public_event_ticket_types(:'eventID'::uuid),
    'Should replace organizer ticket inventory with the public projection'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
