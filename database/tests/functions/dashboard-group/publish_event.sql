-- Tests publishing events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(29);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a0a0000-0000-0000-0000-000000000001'
\set eventCategoryID '3a0a0000-0000-0000-0000-000000000002'
\set eventExternalAbroadID '3a0a0000-0000-0000-0000-00000000003a'
\set eventExternalClearID '3a0a0000-0000-0000-0000-000000000030'
\set eventExternalMissingUrlID '3a0a0000-0000-0000-0000-000000000031'
\set eventExternalReadyID '3a0a0000-0000-0000-0000-000000000032'
\set eventID '3a0a0000-0000-0000-0000-000000000003'
\set eventNoMeetingID '3a0a0000-0000-0000-0000-000000000004'
\set eventNoStartDateID '3a0a0000-0000-0000-0000-000000000005'
\set eventPublishedID '3a0a0000-0000-0000-0000-000000000006'
\set eventTicketedHybridID '3a0a0000-0000-0000-0000-00000000001f'
\set eventTicketedInvalidCurrencyID '3a0a0000-0000-0000-0000-000000000007'
\set eventTicketedFreeID '3a0a0000-0000-0000-0000-00000000001a'
\set eventTicketedNoRecipientID '3a0a0000-0000-0000-0000-000000000008'
\set groupCategoryID '3a0a0000-0000-0000-0000-000000000009'
\set groupExternalID '3a0a0000-0000-0000-0000-000000000033'
\set groupID '3a0a0000-0000-0000-0000-000000000010'
\set groupNoRecipientID '3a0a0000-0000-0000-0000-000000000011'
\set missingGroupID '3a0a0000-0000-0000-0000-000000000012'
\set previousPublisherID '3a0a0000-0000-0000-0000-000000000013'
\set priceWindowExternalAbroadID '3a0a0000-0000-0000-0000-00000000003b'
\set priceWindowExternalClearID '3a0a0000-0000-0000-0000-000000000034'
\set priceWindowExternalMissingUrlID '3a0a0000-0000-0000-0000-000000000035'
\set priceWindowExternalReadyID '3a0a0000-0000-0000-0000-000000000036'
\set priceWindowFreeID '3a0a0000-0000-0000-0000-00000000001b'
\set priceWindowHybridID '3a0a0000-0000-0000-0000-000000000021'
\set priceWindowInvalidCurrencyID '3a0a0000-0000-0000-0000-00000000001c'
\set priceWindowNoRecipientID '3a0a0000-0000-0000-0000-00000000001d'
\set sessionMeetingID '3a0a0000-0000-0000-0000-000000000014'
\set sessionNoMeetingID '3a0a0000-0000-0000-0000-000000000015'
\set sessionPublishedMeetingID '3a0a0000-0000-0000-0000-000000000016'
\set ticketTypeExternalAbroadID '3a0a0000-0000-0000-0000-00000000003c'
\set ticketTypeExternalClearID '3a0a0000-0000-0000-0000-000000000037'
\set ticketTypeExternalMissingUrlID '3a0a0000-0000-0000-0000-000000000038'
\set ticketTypeExternalReadyID '3a0a0000-0000-0000-0000-000000000039'
\set ticketTypeInvalidCurrencyID '3a0a0000-0000-0000-0000-000000000017'
\set ticketTypeFreeID '3a0a0000-0000-0000-0000-00000000001e'
\set ticketTypeHybridID '3a0a0000-0000-0000-0000-000000000020'
\set ticketTypeNoRecipientID '3a0a0000-0000-0000-0000-000000000018'
\set userID '3a0a0000-0000-0000-0000-000000000019'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'previousPublisherID');
select fx_group(:'groupNoRecipientID', :'communityID', :'groupCategoryID');

-- Operator allowlist used by external publish scenarios
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_test_group',
        'seller_display_name', 'Test Fiscal Sponsor'
    )));

-- Allowlisted group with external payments enabled for external publish scenarios
select fx_group(:'groupExternalID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true
));

-- Users
select fx_user(:'userID', jsonb_build_object('username', 'user-publish-event'));

-- Event (unpublished, with meeting_in_sync=true to verify it gets set to false)
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2025-06-01 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', '2025-06-01 10:00:00+00'
));

-- Event without meeting_requested (to verify meeting_in_sync is not changed)
select fx_event(:'eventNoMeetingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '13 hours',
    'meeting_requested', false,
    'starts_at', current_timestamp + interval '12 hours'
));

-- Event already published (to verify publishing is idempotent)
select fx_event(:'eventPublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2025-07-01 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'published_at', '2025-01-01 10:00:00+00',
    'published_by', :'previousPublisherID',
    'starts_at', '2025-07-01 10:00:00+00'
));

-- Event without start date (to verify it cannot be published)
select fx_event(:'eventNoStartDateID', :'groupID', :'eventCategoryID');

-- Ticketed event without a payment recipient on its group
select fx_event(:'eventTicketedNoRecipientID', :'groupNoRecipientID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp + interval '2 days'
));

-- All-zero ticketed event without a payment recipient on its group
select fx_event(:'eventTicketedFreeID', :'groupNoRecipientID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'starts_at', current_timestamp + interval '2 days'
));

-- Ticketed event with an invalid currency code
select fx_event(:'eventTicketedInvalidCurrencyID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USDD',
    'starts_at', current_timestamp + interval '2 days'
));

-- Paid-capable hybrid event with a complete physical venue
select fx_event(:'eventTicketedHybridID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'hybrid',
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp + interval '2 days',
    'venue_address', '123 Main St',
    'venue_city', 'San Francisco',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Community Hall',
    'venue_state_code', 'CA',
    'venue_state_name', 'California',
    'venue_zip_code', '94105'
));

-- Ticket type for the group without a payment recipient
select fx_event_ticket_type(:'ticketTypeNoRecipientID', :'eventTicketedNoRecipientID', jsonb_build_object(
    'seats_total', 50,
    'title', 'Paid ticket'
));

-- Ticket type for the paid hybrid event
select fx_event_ticket_type(:'ticketTypeHybridID', :'eventTicketedHybridID', jsonb_build_object('seats_total', 50));

-- Ticket type for the all-zero event
select fx_event_ticket_type(:'ticketTypeFreeID', :'eventTicketedFreeID', jsonb_build_object('seats_total', 50));

-- Ticket type for the event with an invalid currency code
select fx_event_ticket_type(:'ticketTypeInvalidCurrencyID', :'eventTicketedInvalidCurrencyID', jsonb_build_object(
    'seats_total', 50,
    'title', 'Paid ticket'
));

-- Price windows determine whether each ticketed event is paid-capable.
select fx_event_ticket_price_window(:'priceWindowFreeID', :'ticketTypeFreeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'priceWindowHybridID', :'ticketTypeHybridID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'priceWindowInvalidCurrencyID', :'ticketTypeInvalidCurrencyID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'priceWindowNoRecipientID', :'ticketTypeNoRecipientID', jsonb_build_object('amount_minor', 2500));

-- Paid external draft whose venue sits outside the group country
select fx_event(:'eventExternalAbroadID', :'groupExternalID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/abroad',
    'payment_currency_code', 'KRW',
    'starts_at', current_timestamp + interval '2 days',
    'venue_address', '1 Test Street',
    'venue_city', 'Tokyo',
    'venue_country_code', 'JP',
    'venue_name', 'Test Hall',
    'venue_zip_code', '100-0001'
));

-- Paid non-external draft that still carries a leftover external URL
select fx_event(:'eventExternalClearID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/leftover-publish',
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp + interval '2 days',
    'venue_address', '123 Main St',
    'venue_city', 'San Francisco',
    'venue_country_code', 'US',
    'venue_name', 'Community Hall',
    'venue_zip_code', '94105'
));

-- Paid external draft missing the required payment URL
select fx_event(:'eventExternalMissingUrlID', :'groupExternalID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'KRW',
    'starts_at', current_timestamp + interval '2 days',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Paid external draft ready to publish without Stripe
select fx_event(:'eventExternalReadyID', :'groupExternalID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/publish',
    'payment_currency_code', 'KRW',
    'starts_at', current_timestamp + interval '2 days',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Ticket types for the external publish fixtures
select fx_event_ticket_type(:'ticketTypeExternalAbroadID', :'eventExternalAbroadID', jsonb_build_object('seats_total', 50));
select fx_event_ticket_type(:'ticketTypeExternalClearID', :'eventExternalClearID', jsonb_build_object('seats_total', 50));
select fx_event_ticket_type(:'ticketTypeExternalMissingUrlID', :'eventExternalMissingUrlID', jsonb_build_object('seats_total', 50));
select fx_event_ticket_type(:'ticketTypeExternalReadyID', :'eventExternalReadyID', jsonb_build_object('seats_total', 50));

-- Price windows for the external publish fixtures
select fx_event_ticket_price_window(:'priceWindowExternalAbroadID', :'ticketTypeExternalAbroadID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'priceWindowExternalClearID', :'ticketTypeExternalClearID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'priceWindowExternalMissingUrlID', :'ticketTypeExternalMissingUrlID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'priceWindowExternalReadyID', :'ticketTypeExternalReadyID', jsonb_build_object('amount_minor', 5000));

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
            community_id,
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
            'user-publish-event',
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'event',
            %L::uuid
        )
        $$,
        :'userID',
        :'communityID',
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
    'OCG01',
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
    'OCG01',
    'event must have a start date to be published',
    'Should throw error when event has no start date'
);

-- Should publish all-zero ticketed events without payment setup
select lives_ok(
    format(
        'select publish_event(%L::uuid, %L::uuid, %L::uuid, null)',
        :'userID',
        :'groupNoRecipientID',
        :'eventTicketedFreeID'
    ),
    'Should publish all-zero ticketed events without payment setup'
);

-- Should publish a paid-capable hybrid event with a complete physical venue
select lives_ok(
    format(
        $$select publish_event(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'stripe',
            '{
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_test_group",
                    "seller_display_name": "Test Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_test_group",
                    "seller_display_name": "Test Fiscal Sponsor"
                }
            }'::jsonb
        )$$,
        :'userID',
        :'groupID',
        :'eventTicketedHybridID'
    ),
    'Should publish a paid-capable hybrid event with a complete physical venue'
);

select is(
    (
        select jsonb_build_object(
            'event_kind_id', event_kind_id,
            'published', published,
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
        where event_id = :'eventTicketedHybridID'::uuid
    ),
    '{
        "event_kind_id": "hybrid",
        "published": true,
        "venue_address": "123 Main St",
        "venue_city": "San Francisco",
        "venue_country_code": "US",
        "venue_country_name": "United States",
        "venue_name": "Community Hall",
        "venue_state_code": "CA",
        "venue_state_name": "California",
        "venue_zip_code": "94105"
    }'::jsonb,
    'Should retain paid hybrid eligibility data when publishing'
);

-- Should throw error when paid-capable event group has no payment recipient
select throws_ok(
    format(
        $$select publish_event(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'stripe',
            '{
                "expected_payment_recipient": null,
                "require_automatic_tax": true,
                "validated_payment_recipient": null
            }'::jsonb
        )$$,
        :'userID',
        :'groupNoRecipientID',
        :'eventTicketedNoRecipientID'
    ),
    'OCG01',
    'paid-capable events require a payment recipient',
    'Should throw error when paid-capable event group has no payment recipient'
);

-- Should reject publication validated against a stale sponsor
select throws_ok(
    format(
        $$select publish_event(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'stripe',
            '{
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_stale",
                    "seller_display_name": "Stale Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_stale",
                    "seller_display_name": "Stale Fiscal Sponsor"
                }
            }'::jsonb
        )$$,
        :'userID',
        :'groupID',
        :'eventTicketedInvalidCurrencyID'
    ),
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject publication validated against a stale sponsor'
);

-- Should reject ticketed events whose currency code is unsupported
select throws_ok(
    format(
        $$select publish_event(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'stripe',
            '{
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_test_group",
                    "seller_display_name": "Test Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_test_group",
                    "seller_display_name": "Test Fiscal Sponsor"
                }
            }'::jsonb
        )$$,
        :'userID',
        :'groupID',
        :'eventTicketedInvalidCurrencyID'
    ),
    'OCG01',
    'payment_currency_code must be a supported currency code',
    'Should reject ticketed events whose currency code is unsupported'
);

-- Should reject publishing an external URL when the group is not currently eligible
select throws_ok(
    format(
        $$select publish_event(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'stripe',
            '{
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_test_group",
                    "seller_display_name": "Test Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_test_group",
                    "seller_display_name": "Test Fiscal Sponsor"
                }
            }'::jsonb
        )$$,
        :'userID',
        :'groupID',
        :'eventExternalClearID'
    ),
    'OCG01',
    'external payments are not available for this event',
    'Should reject publishing an external URL when the group is not currently eligible'
);

select is(
    (
        select jsonb_build_object(
            'external_payment_url', external_payment_url,
            'published', published
        )
        from event
        where event_id = :'eventExternalClearID'::uuid
    ),
    '{"external_payment_url": "https://pay.example.test/leftover-publish", "published": false}'::jsonb,
    'Should reject publishing an external URL when the group is not currently eligible'
);

-- Should publish a paid external event without Stripe recipient validation
select lives_ok(
    format(
        'select publish_event(%L::uuid, %L::uuid, %L::uuid, null)',
        :'userID',
        :'groupExternalID',
        :'eventExternalReadyID'
    ),
    'Should publish a paid external event without Stripe recipient validation'
);

select is(
    (
        select jsonb_build_object(
            'external_payment_url', external_payment_url,
            'published', published
        )
        from event
        where event_id = :'eventExternalReadyID'::uuid
    ),
    '{
        "external_payment_url": "https://pay.example.test/publish",
        "published": true
    }'::jsonb,
    'Should preserve the external payment URL when publishing in external mode'
);

-- Should reject publishing a paid external event without a payment URL
select throws_ok(
    format(
        'select publish_event(%L::uuid, %L::uuid, %L::uuid, null)',
        :'userID',
        :'groupExternalID',
        :'eventExternalMissingUrlID'
    ),
    'OCG01',
    'paid-capable events require a valid external payment url',
    'Should reject publishing a paid external event without a payment URL'
);

-- Should reject publishing a paid external event with a venue outside the group country
select throws_ok(
    format(
        'select publish_event(%L::uuid, %L::uuid, %L::uuid, null)',
        :'userID',
        :'groupExternalID',
        :'eventExternalAbroadID'
    ),
    'OCG01',
    'external paid events require a venue in the group country',
    'Should reject publishing a paid external event with a venue outside the group country'
);

select is(
    (select published from event where event_id = :'eventExternalAbroadID'::uuid),
    false,
    'Should keep the external event unpublished when its venue is outside the group country'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
