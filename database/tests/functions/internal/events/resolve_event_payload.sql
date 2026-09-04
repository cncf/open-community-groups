-- Tests resolving the event columns and ticket configuration from a payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(16);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f3010000-0000-0000-0000-000000000001'
\set discountCodeID 'f3010000-0000-0000-0000-000000000002'
\set eventCategoryID 'f3010000-0000-0000-0000-000000000003'
\set eventID 'f3010000-0000-0000-0000-000000000004'
\set groupCategoryID 'f3010000-0000-0000-0000-000000000005'
\set groupID 'f3010000-0000-0000-0000-000000000006'
\set priceWindowID 'f3010000-0000-0000-0000-000000000007'
\set ticketTypeID 'f3010000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Stored paid event with external, tax, currency, venue and questionnaire state
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_instructions', 'Wire the purchase ID.',
    'external_payment_url', 'https://pay.example.test/event',
    'external_payment_window_hours', 72,
    'manual_tax_rate_ids', jsonb_build_array('txr_state'),
    'meeting_recording_published', true,
    'payment_currency_code', 'USD',
    'registration_questions', jsonb_build_array(jsonb_build_object(
        'id', 'q1',
        'kind', 'text',
        'label', 'Company',
        'required', false
    )),
    'tax_behavior', 'exclusive',
    'tax_calculation_mode', 'manual',
    'venue_country_code', 'US',
    'venue_state_code', 'OR',
    'venue_state_name', 'Oregon'
));

-- Stored discount code of the event
insert into event_discount_code (event_discount_code_id, event_id, code, kind, title, percentage)
values (:'discountCodeID', :'eventID', 'SAVE10', 'percentage', 'Save 10', 10);

-- Stored paid ticket tier of the event
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('title', 'General'));
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 2500));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should apply defaults and normalize a new event payload
select is(
    (
        select jsonb_build_object(
            'attendee_approval_required', (r.resolved).attendee_approval_required,
            'banner_url', (r.resolved).banner_url,
            'event_category_id', (r.resolved).event_category_id,
            'event_kind_id', (r.resolved).event_kind_id,
            'event_reminder_enabled', (r.resolved).event_reminder_enabled,
            'manual_tax_rate_ids', to_jsonb((r.resolved).manual_tax_rate_ids),
            'meeting_hosts', to_jsonb((r.resolved).meeting_hosts),
            'meeting_provider_id', (r.resolved).meeting_provider_id,
            'meeting_recording_published', (r.resolved).meeting_recording_published,
            'meeting_recording_requested', (r.resolved).meeting_recording_requested,
            'name', (r.resolved).name,
            'payment_currency_code', (r.resolved).payment_currency_code,
            'registration_questions', (r.resolved).registration_questions,
            'tags', to_jsonb((r.resolved).tags),
            'tax_behavior', (r.resolved).tax_behavior,
            'tax_calculation_mode', (r.resolved).tax_calculation_mode,
            'test_event', (r.resolved).test_event,
            'timezone', (r.resolved).timezone,
            'venue_address', (r.resolved).venue_address,
            'venue_country_code', (r.resolved).venue_country_code,
            'venue_state_code', (r.resolved).venue_state_code,
            'venue_state_name', (r.resolved).venue_state_name,
            'waitlist_enabled', (r.resolved).waitlist_enabled
        )
        from resolve_event_payload(
            format('{
                "banner_url": "",
                "category_id": "%s",
                "kind_id": "virtual",
                "meeting_hosts": ["host@example.test"],
                "meeting_provider_id": "",
                "name": "Resolved Event",
                "tags": ["a", "b"],
                "timezone": "America/New_York",
                "venue_address": "  1 Main St  ",
                "venue_country_code": " us ",
                "venue_state": "  Oregon ",
                "venue_state_code": "or"
            }', :'eventCategoryID')::jsonb,
            null::event,
            false
        ) r
    ),
    format('{
        "attendee_approval_required": false,
        "banner_url": null,
        "event_category_id": "%s",
        "event_kind_id": "virtual",
        "event_reminder_enabled": true,
        "manual_tax_rate_ids": [],
        "meeting_hosts": ["host@example.test"],
        "meeting_provider_id": null,
        "meeting_recording_published": false,
        "meeting_recording_requested": true,
        "name": "Resolved Event",
        "payment_currency_code": null,
        "registration_questions": [],
        "tags": ["a", "b"],
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "automatic",
        "test_event": false,
        "timezone": "America/New_York",
        "venue_address": "1 Main St",
        "venue_country_code": "US",
        "venue_state_code": "OR",
        "venue_state_name": "Oregon",
        "waitlist_enabled": false
    }', :'eventCategoryID')::jsonb,
    'Should apply defaults and normalize a new event payload'
);

-- Should give a new event without ticket types a single free public tier
select is(
    (
        select jsonb_build_object(
            'capacity', (r.resolved).capacity,
            'discount_codes', r.discount_codes,
            'external_mode', r.external_mode,
            'ticket_types', (
                select jsonb_agg(
                    (tt - 'event_ticket_type_id')
                    || jsonb_build_object('price_windows', (
                        select jsonb_agg(pw - 'event_ticket_price_window_id')
                        from jsonb_array_elements(tt->'price_windows') pw
                    ))
                )
                from jsonb_array_elements(r.ticket_types) tt
            )
        )
        from resolve_event_payload('{"name": "Free Event", "timezone": "UTC"}'::jsonb, null::event, true) r
    ),
    '{
        "capacity": 500,
        "discount_codes": null,
        "external_mode": false,
        "ticket_types": [{
            "active": true,
            "availability": "public",
            "order": 1,
            "price_windows": [{"amount_minor": 0}],
            "seats_total": 500,
            "title": "General Admission"
        }]
    }'::jsonb,
    'Should give a new event without ticket types a single free public tier'
);

-- Should give a new event with null ticket types the default tier
select is(
    (
        select r.ticket_types->0->>'title'
        from resolve_event_payload('{"ticket_types": null, "timezone": "UTC"}'::jsonb, null::event, false) r
    ),
    'General Admission',
    'Should give a new event with null ticket types the default tier'
);

-- Should keep the submitted ticket types and discount codes of a new event
select is(
    (
        select jsonb_build_object(
            'capacity', (r.resolved).capacity,
            'discount_codes', r.discount_codes,
            'ticket_types', r.ticket_types
        )
        from resolve_event_payload(
            '{
                "discount_codes": [{"code": "SAVE10"}],
                "ticket_types": [{"seats_total": 25, "price_windows": [{"amount_minor": 1000}]}],
                "timezone": "UTC"
            }'::jsonb,
            null::event,
            false
        ) r
    ),
    '{
        "capacity": 25,
        "discount_codes": [{"code": "SAVE10"}],
        "ticket_types": [{"seats_total": 25, "price_windows": [{"amount_minor": 1000}]}]
    }'::jsonb,
    'Should keep the submitted ticket types and discount codes of a new event'
);

-- Should preserve stored values for keys omitted from an update payload
select is(
    (
        select jsonb_build_object(
            'discount_codes', jsonb_array_length(r.discount_codes),
            'external_payment_instructions', (r.resolved).external_payment_instructions,
            'external_payment_url', (r.resolved).external_payment_url,
            'external_payment_window_hours', (r.resolved).external_payment_window_hours,
            'manual_tax_rate_ids', to_jsonb((r.resolved).manual_tax_rate_ids),
            'meeting_recording_published', (r.resolved).meeting_recording_published,
            'payment_currency_code', (r.resolved).payment_currency_code,
            'registration_questions', jsonb_array_length((r.resolved).registration_questions),
            'tax_behavior', (r.resolved).tax_behavior,
            'tax_calculation_mode', (r.resolved).tax_calculation_mode,
            'ticket_types', r.ticket_types->0->>'title',
            'venue_state_code', (r.resolved).venue_state_code
        )
        from resolve_event_payload(
            '{"name": "Renamed", "timezone": "UTC", "venue_country_code": "US", "venue_state_name": "Oregon"}'::jsonb,
            (select e from event e where e.event_id = :'eventID'),
            true
        ) r
    ),
    '{
        "discount_codes": 1,
        "external_payment_instructions": "Wire the purchase ID.",
        "external_payment_url": "https://pay.example.test/event",
        "external_payment_window_hours": 72,
        "manual_tax_rate_ids": [],
        "meeting_recording_published": true,
        "payment_currency_code": "USD",
        "registration_questions": 1,
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "none",
        "ticket_types": "General",
        "venue_state_code": "OR"
    }'::jsonb,
    'Should preserve stored values for keys omitted from an update payload'
);

-- Should keep stored provider tax settings when the group cannot collect externally
select is(
    (
        select jsonb_build_object(
            'external_mode', r.external_mode,
            'external_payment_url', (r.resolved).external_payment_url,
            'manual_tax_rate_ids', to_jsonb((r.resolved).manual_tax_rate_ids),
            'tax_behavior', (r.resolved).tax_behavior,
            'tax_calculation_mode', (r.resolved).tax_calculation_mode
        )
        from resolve_event_payload(
            '{"external_payment_url": "", "timezone": "UTC"}'::jsonb,
            (select e from event e where e.event_id = :'eventID'),
            false
        ) r
    ),
    '{
        "external_mode": false,
        "external_payment_url": null,
        "manual_tax_rate_ids": ["txr_state"],
        "tax_behavior": "exclusive",
        "tax_calculation_mode": "manual"
    }'::jsonb,
    'Should keep stored provider tax settings when the group cannot collect externally'
);

-- Should apply submitted values over stored ones
select is(
    (
        select jsonb_build_object(
            'discount_codes', r.discount_codes,
            'external_payment_window_hours', (r.resolved).external_payment_window_hours,
            'manual_tax_rate_ids', to_jsonb((r.resolved).manual_tax_rate_ids),
            'meeting_recording_published', (r.resolved).meeting_recording_published,
            'payment_currency_code', (r.resolved).payment_currency_code,
            'registration_questions', (r.resolved).registration_questions,
            'tax_behavior', (r.resolved).tax_behavior,
            'tax_calculation_mode', (r.resolved).tax_calculation_mode,
            'ticket_types', r.ticket_types
        )
        from resolve_event_payload(
            '{
                "discount_codes": null,
                "external_payment_url": "",
                "external_payment_window_hours": "",
                "manual_tax_rate_ids": null,
                "meeting_recording_published": false,
                "payment_currency_code": "EUR",
                "registration_questions": [],
                "tax_behavior": "",
                "tax_calculation_mode": "automatic",
                "ticket_types": null,
                "timezone": "UTC"
            }'::jsonb,
            (select e from event e where e.event_id = :'eventID'),
            false
        ) r
    ),
    '{
        "discount_codes": null,
        "external_payment_window_hours": null,
        "manual_tax_rate_ids": [],
        "meeting_recording_published": false,
        "payment_currency_code": "EUR",
        "registration_questions": [],
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "automatic",
        "ticket_types": null
    }'::jsonb,
    'Should apply submitted values over stored ones'
);

-- Should force inclusive display when the payload collects no tax
select is(
    (
        select (r.resolved).tax_behavior
        from resolve_event_payload(
            '{"tax_behavior": "exclusive", "tax_calculation_mode": "none", "timezone": "UTC"}'::jsonb,
            null::event,
            false
        ) r
    ),
    'inclusive',
    'Should force inclusive display when the payload collects no tax'
);

-- Should apply a submitted subdivision code
select is(
    (
        select (r.resolved).venue_state_code
        from resolve_event_payload(
            '{"timezone": "UTC", "venue_country_code": "US", "venue_state_code": " wa ", "venue_state_name": "Washington"}'::jsonb,
            (select e from event e where e.event_id = :'eventID'),
            true
        ) r
    ),
    'WA',
    'Should apply a submitted subdivision code'
);

-- Should clear a stored subdivision code when the country changes
select is(
    (
        select (r.resolved).venue_state_code
        from resolve_event_payload(
            '{"timezone": "UTC", "venue_country_code": "CA", "venue_state_name": "Oregon"}'::jsonb,
            (select e from event e where e.event_id = :'eventID'),
            true
        ) r
    ),
    null::text,
    'Should clear a stored subdivision code when the country changes'
);

-- Should clear a stored subdivision code when the legacy state name changes
select is(
    (
        select (r.resolved).venue_state_code
        from resolve_event_payload(
            '{"timezone": "UTC", "venue_country_code": "US", "venue_state": "Washington"}'::jsonb,
            (select e from event e where e.event_id = :'eventID'),
            true
        ) r
    ),
    null::text,
    'Should clear a stored subdivision code when the legacy state name changes'
);

-- Should keep a stored subdivision code when the payload omits the state entirely
select is(
    (
        select (r.resolved).venue_state_code
        from resolve_event_payload(
            '{"timezone": "UTC", "venue_country_code": "US"}'::jsonb,
            (select e from event e where e.event_id = :'eventID'),
            true
        ) r
    ),
    'OR',
    'Should keep a stored subdivision code when the payload omits the state entirely'
);

-- Should leave caller-owned columns null
select is(
    (
        select jsonb_build_object(
            'created_by', (r.resolved).created_by,
            'event_id', (r.resolved).event_id,
            'group_id', (r.resolved).group_id,
            'meeting_in_sync', (r.resolved).meeting_in_sync,
            'published', (r.resolved).published,
            'slug', (r.resolved).slug
        )
        from resolve_event_payload(
            '{"timezone": "UTC"}'::jsonb,
            (select e from event e where e.event_id = :'eventID'),
            true
        ) r
    ),
    '{"created_by": null, "event_id": null, "group_id": null, "meeting_in_sync": null, "published": null, "slug": null}'::jsonb,
    'Should leave caller-owned columns null'
);

-- Should parse timestamps in the payload timezone
select is(
    (
        select array[
            (r.resolved).cfs_starts_at,
            (r.resolved).ends_at,
            (r.resolved).registration_ends_at,
            (r.resolved).registration_starts_at,
            (r.resolved).starts_at
        ]
        from resolve_event_payload(
            '{
                "cfs_starts_at": "2030-01-01T08:00:00",
                "ends_at": "2030-01-01T11:00:00",
                "registration_ends_at": "2030-01-01T10:00:00",
                "registration_starts_at": "2030-01-01T09:00:00",
                "starts_at": "2030-01-01T10:00:00",
                "timezone": "Europe/Madrid"
            }'::jsonb,
            null::event,
            false
        ) r
    ),
    array[
        '2030-01-01 07:00:00+00',
        '2030-01-01 10:00:00+00',
        '2030-01-01 09:00:00+00',
        '2030-01-01 08:00:00+00',
        '2030-01-01 09:00:00+00'
    ]::timestamptz[],
    'Should parse timestamps in the payload timezone'
);

-- Should reject an external URL when the group cannot collect externally
select throws_ok(
    $$select * from resolve_event_payload(
        '{"external_payment_url": "https://pay.example.test/event", "timezone": "UTC"}'::jsonb,
        null::event,
        false
    )$$,
    'OCG01',
    'external payments are not available for this event',
    'Should reject an external URL when the group cannot collect externally'
);

-- Should select the external rail for paid events in an eligible group
select is(
    (
        select jsonb_build_object(
            'external_mode', r.external_mode,
            'external_payment_url', (r.resolved).external_payment_url,
            'tax_calculation_mode', (r.resolved).tax_calculation_mode
        )
        from resolve_event_payload(
            '{
                "external_payment_url": "https://pay.example.test/event",
                "tax_calculation_mode": "automatic",
                "ticket_types": [{"price_windows": [{"amount_minor": 1000}]}],
                "timezone": "UTC"
            }'::jsonb,
            null::event,
            true
        ) r
    ),
    '{"external_mode": true, "external_payment_url": "https://pay.example.test/event", "tax_calculation_mode": "none"}'::jsonb,
    'Should select the external rail for paid events in an eligible group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
