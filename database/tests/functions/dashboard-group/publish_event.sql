-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a2b0000-0000-0000-0000-000000000001'
\set eventCategoryID '3a2b0000-0000-0000-0000-000000000002'
\set eventID '3a2b0000-0000-0000-0000-000000000003'
\set eventNoMeetingID '3a2b0000-0000-0000-0000-000000000004'
\set eventNoStartDateID '3a2b0000-0000-0000-0000-000000000005'
\set eventPublishedID '3a2b0000-0000-0000-0000-000000000006'
\set eventTicketedInvalidCurrencyID '3a2b0000-0000-0000-0000-000000000007'
\set eventTicketedNoRecipientID '3a2b0000-0000-0000-0000-000000000008'
\set groupCategoryID '3a2b0000-0000-0000-0000-000000000009'
\set groupID '3a2b0000-0000-0000-0000-000000000010'
\set groupNoRecipientID '3a2b0000-0000-0000-0000-000000000011'
\set missingGroupID '3a2b0000-0000-0000-0000-000000000012'
\set previousPublisherID '3a2b0000-0000-0000-0000-000000000013'
\set sessionMeetingID '3a2b0000-0000-0000-0000-000000000014'
\set sessionNoMeetingID '3a2b0000-0000-0000-0000-000000000015'
\set sessionPublishedMeetingID '3a2b0000-0000-0000-0000-000000000016'
\set ticketTypeInvalidCurrencyID '3a2b0000-0000-0000-0000-000000000017'
\set ticketTypeNoRecipientID '3a2b0000-0000-0000-0000-000000000018'
\set userID '3a2b0000-0000-0000-0000-000000000019'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'test-alliance',
    'Test Alliance',
    'A test alliance',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    description,
    payment_recipient
) values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'A test group',
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_test_group')
);

-- Group without a payment recipient
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'groupNoRecipientID',
    :'allianceID',
    :'groupCategoryID',
    'No Recipient Group',
    'no-recipient-group',
    'A group without a payment recipient'
);

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'userID', 'publisher-hash', 'user@test.local', 'user'),
    (:'previousPublisherID', 'previous-publisher-hash', 'publisher@test.local', 'publisher');

-- Event (unpublished, with meeting_in_sync=true to verify it gets set to false)
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

    capacity,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    published
) values (
    :'eventID',
    :'groupID',
    'Test Event',
    'test-event',
    'A test event',
    'UTC',
    :'eventCategoryID',
    'virtual',
    '2025-06-01 10:00:00+00',
    '2025-06-01 11:00:00+00',

    100,
    true,
    'zoom',
    true,
    false
);

-- Event without meeting_requested (to verify meeting_in_sync is not changed)
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
    meeting_in_sync,
    meeting_requested,
    published
) values (
    :'eventNoMeetingID',
    :'groupID',
    'Test Event No Meeting',
    'test-event-no-meeting',
    'A test event without meeting',
    'UTC',
    :'eventCategoryID',
    'in-person',
    current_timestamp + interval '12 hours',
    current_timestamp + interval '13 hours',
    null,
    false,
    false
);

-- Event already published (to verify publishing is idempotent)
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

    capacity,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    published,
    published_at,
    published_by
) values (
    :'eventPublishedID',
    :'groupID',
    'Already Published Event',
    'already-published-event',
    'An already published event',
    'UTC',
    :'eventCategoryID',
    'virtual',
    '2025-07-01 10:00:00+00',
    '2025-07-01 11:00:00+00',

    100,
    true,
    'zoom',
    true,
    true,
    '2025-01-01 10:00:00+00',
    :'previousPublisherID'
);

-- Event without start date (to verify it cannot be published)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published
) values (
    :'eventNoStartDateID',
    :'groupID',
    'Test Event No Start Date',
    'test-event-no-start-date',
    'A test event without start date',
    'UTC',
    :'eventCategoryID',
    'in-person',
    false
);

-- Ticketed event without a payment recipient on its group
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
    payment_currency_code,
    published
) values (
    :'eventTicketedNoRecipientID',
    :'groupNoRecipientID',
    'Ticketed Event No Recipient',
    'ticketed-event-no-recipient',
    'A ticketed event without a payment recipient',
    'UTC',
    :'eventCategoryID',
    'virtual',
    current_timestamp + interval '2 days',
    'USD',
    false
);

-- Ticketed event with an invalid currency code
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
    payment_currency_code,
    published
) values (
    :'eventTicketedInvalidCurrencyID',
    :'groupID',
    'Ticketed Event Invalid Currency',
    'ticketed-event-invalid-currency',
    'A ticketed event with an invalid currency code',
    'UTC',
    :'eventCategoryID',
    'virtual',
    current_timestamp + interval '2 days',
    'USDD',
    false
);

-- Ticket type for the group without a payment recipient
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeNoRecipientID',
    :'eventTicketedNoRecipientID',
    1,
    50,
    'Paid ticket'
);

-- Ticket type for the event with an invalid currency code
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeInvalidCurrencyID',
    :'eventTicketedInvalidCurrencyID',
    1,
    50,
    'Paid ticket'
);

-- Session with meeting_requested=true (should be marked as out of sync)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionMeetingID',
    :'eventID',
    'Session With Meeting',
    '2025-06-01 10:00:00+00',
    '2025-06-01 10:30:00+00',
    'virtual',
    true,
    'zoom',
    true
);

-- Session for the already published event (should not be marked out of sync)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionPublishedMeetingID',
    :'eventPublishedID',
    'Already Published Session',
    '2025-07-01 10:00:00+00',
    '2025-07-01 10:30:00+00',
    'virtual',
    true,
    'zoom',
    true
);

-- Session with meeting_requested=false (should NOT be marked as out of sync)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_requested
) values (
    :'sessionNoMeetingID',
    :'eventID',
    'Session Without Meeting',
    '2025-06-01 10:30:00+00',
    '2025-06-01 11:00:00+00',
    'in-person',
    null,
    false
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should set published and metadata
select lives_ok(
    format(
        'select publish_event(%L::uuid, %L::uuid, %L::uuid, null)',
        :'userID',
        :'groupID',
        :'eventID'
    ),
    'Should set published and metadata'
);

-- Should set published=true
select is(
    (select published from event where event_id = :'eventID'),
    true,
    'Should set published=true'
);

-- Should set published_at timestamp
select isnt(
    (select published_at from event where event_id = :'eventID'),
    null,
    'Should set published_at timestamp'
);

-- Should set published_by to the user
select is(
    (select published_by from event where event_id = :'eventID')::text,
    :'userID',
    'Should set published_by to the user'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            alliance_id,
            group_id,
            event_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'event_published',
            %L::uuid,
            'user',
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'event',
            %L::uuid
        )
        $$,
        :'userID',
        :'allianceID',
        :'groupID',
        :'eventID',
        :'eventID'
    ),
    'Should create the expected audit row'
);

-- Should set event meeting_in_sync to false
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    false,
    'Should set event meeting_in_sync=false'
);

-- Should set session meeting_in_sync to false when meeting_requested=true
select is(
    (select meeting_in_sync from session where session_id = :'sessionMeetingID'),
    false,
    'Should set session meeting_in_sync=false when meeting_requested=true'
);

-- Should not change session meeting_in_sync when meeting_requested=false
select is(
    (select meeting_in_sync from session where session_id = :'sessionNoMeetingID'),
    null,
    'Should not change session meeting_in_sync when meeting_requested=false'
);

-- Should leave an already published event unchanged
select lives_ok(
    format(
        'select publish_event(%L::uuid, %L::uuid, %L::uuid, null)',
        :'userID',
        :'groupID',
        :'eventPublishedID'
    ),
    'Should leave an already published event unchanged'
);

-- Should preserve already published event metadata and meeting sync
select results_eq(
    format(
        $$
        select
            e.meeting_in_sync,
            e.published_at,
            e.published_by,
            s.meeting_in_sync
        from event e
        join session s on s.event_id = e.event_id
        where e.event_id = %L::uuid
        $$,
        :'eventPublishedID'
    ),
    format(
        $$
        values (
            true,
            '2025-01-01 10:00:00+00'::timestamptz,
            %L::uuid,
            true
        )
        $$,
        :'previousPublisherID'
    ),
    'Should preserve already published event metadata and meeting sync'
);

-- Should not create an audit row when publishing is a no-op
select is(
    (select count(*)::int from audit_log where action = 'event_published'),
    1,
    'Should not create an audit row when publishing is a no-op'
);

-- Should publish event when meeting_requested=false
select lives_ok(
    format(
        'select publish_event(%L::uuid, %L::uuid, %L::uuid, null)',
        :'userID',
        :'groupID',
        :'eventNoMeetingID'
    ),
    'Should publish event when meeting_requested=false'
);

-- Should keep event meeting_in_sync unchanged when meeting_requested=false
select is(
    (select meeting_in_sync from event where event_id = :'eventNoMeetingID'),
    null,
    'Should keep event meeting_in_sync unchanged when meeting_requested=false'
);

-- Should mark reminder as evaluated when publishing event within 24 hours
select is(
    (select event_reminder_evaluated_for_starts_at from event where event_id = :'eventNoMeetingID'),
    (select starts_at from event where event_id = :'eventNoMeetingID'),
    'Should mark reminder as evaluated when publishing event within 24 hours'
);

-- Should throw error when group_id does not match
select throws_ok(
    format(
        'select publish_event(%L::uuid, %L::uuid, %L::uuid, null)',
        :'userID',
        :'missingGroupID',
        :'eventID'
    ),
    'event not found or inactive',
    'Should throw error when group_id does not match'
);

-- Should throw error when event has no start date
select throws_ok(
    format(
        'select publish_event(%L::uuid, %L::uuid, %L::uuid, null)',
        :'userID',
        :'groupID',
        :'eventNoStartDateID'
    ),
    'event must have a start date to be published',
    'Should throw error when event has no start date'
);

-- Should throw error when ticketed event group has no payment recipient
select throws_ok(
    format(
        'select publish_event(%L::uuid, %L::uuid, %L::uuid, ''stripe'')',
        :'userID',
        :'groupNoRecipientID',
        :'eventTicketedNoRecipientID'
    ),
    'ticketed events require a payment recipient',
    'Should throw error when ticketed event group has no payment recipient'
);

-- Should reject ticketed events whose currency code is unsupported
select throws_ok(
    format(
        'select publish_event(%L::uuid, %L::uuid, %L::uuid, ''stripe'')',
        :'userID',
        :'groupID',
        :'eventTicketedInvalidCurrencyID'
    ),
    'payment_currency_code must be a supported currency code',
    'Should reject ticketed events whose currency code is unsupported'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
