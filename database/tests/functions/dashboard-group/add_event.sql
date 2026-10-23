-- Tests adding events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(41);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a020000-0000-0000-0000-000000000001'
\set eventCategoryID '3a020000-0000-0000-0000-000000000011'
\set groupCategoryID '3a020000-0000-0000-0000-000000000010'
\set groupExternalID '3a020000-0000-0000-0000-0000000000a0'
\set groupExternalNamelessID '3a020000-0000-0000-0000-0000000000b1'
\set groupID '3a020000-0000-0000-0000-000000000002'
\set labelAiID '3a020000-0000-0000-0000-000000000701'
\set labelDuplicate1ID '3a020000-0000-0000-0000-000000000702'
\set labelDuplicate2ID '3a020000-0000-0000-0000-000000000703'
\set labelFailedID '3a020000-0000-0000-0000-000000000704'
\set labelMissingID '3a020000-0000-0000-0000-000000000705'
\set labelWebID '3a020000-0000-0000-0000-000000000706'
\set outsiderUserID '3a020000-0000-0000-0000-000000000023'
\set sponsor1ID '3a020000-0000-0000-0000-000000000061'
\set sponsor2ID '3a020000-0000-0000-0000-000000000062'
\set user1ID '3a020000-0000-0000-0000-000000000020'
\set user2ID '3a020000-0000-0000-0000-000000000021'
\set user3ID '3a020000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================


-- Operator allowlist and window limits used by external paid-event scenarios
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Community
select fx_community(:'communityID', jsonb_build_object('logo_url', 'https://example.com/logo.png'));

-- Baseline categories
select fx_group_category(:'groupCategoryID', :'communityID');

-- Users
select fx_user(:'user1ID', jsonb_build_object(
    'email', 'host1@example.com',
    'name', 'Host One',
    'username', 'host1'
));
select fx_user(:'user2ID', jsonb_build_object(
    'email', 'host2@example.com',
    'name', 'Host Two',
    'username', 'host2'
));
select fx_user(:'user3ID', jsonb_build_object(
    'name', 'Speaker One',
    'username', 'speaker1'
));

-- User outside the group team rejected as an organizer
select fx_user(:'outsiderUserID', jsonb_build_object('username', 'outsider-add-event'));

-- Event Category
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'Conference'));

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', '{"provider": "stripe", "recipient_id": "acct_add_event", "seller_display_name": "Add Event Fiscal Sponsor"}'::jsonb));

-- Allowlisted group with external payments enabled for paid external creates
select fx_group(:'groupExternalID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'external_payments_seller_display_name', 'External Payee Co'
));

-- Allowlisted enabled group that kept a Stripe sponsor but never named the external payee
select fx_group(:'groupExternalNamelessID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_nameless_add", "seller_display_name": "Retained Fiscal Sponsor"}'::jsonb
));

-- Group Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values
    (
        :'sponsor1ID',
        :'groupID',
        'TechCorp',
        'https://example.com/techcorp.png',
        'https://techcorp.com'
    ),
    (:'sponsor2ID', :'groupID', 'CloudInc', 'https://example.com/cloudinc.png', null);

-- Group Team
insert into group_team (accepted, group_id, role, user_id, "order")
values
    (true, :'groupID', 'admin', :'user1ID', 2),
    (false, :'groupID', 'events-manager', :'user2ID', 1),
    (true, :'groupID', 'viewer', :'user3ID', null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject event creation validated against a stale sponsor
select throws_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{
                "_payment_validation": {
                    "expected_payment_recipient": {
                        "provider": "stripe",
                        "recipient_id": "acct_stale",
                        "seller_display_name": "Stale Sponsor"
                    },
                    "require_automatic_tax": true,
                    "validated_payment_recipient": {
                        "provider": "stripe",
                        "recipient_id": "acct_stale",
                        "seller_display_name": "Stale Sponsor"
                    }
                },
                "tax_calculation_mode": "automatic",
                "ticket_types": [
                    {
                        "active": true,
                        "event_ticket_type_id": "3a020000-0000-0000-0000-000000000094",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 2500,
                                "event_ticket_price_window_id": "3a020000-0000-0000-0000-000000000095"
                            }
                        ],
                        "seats_total": 10,
                        "title": "General"
                    }
                ]
            }'::jsonb,
            null::jsonb,
            'stripe'
        )$$,
        :'groupID'
    ),
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject event creation validated against a stale sponsor'
);

-- Should create event with minimal required fields and return expected structure
select ok(
    (select (
        get_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            add_event(
                null::uuid,
                :'groupID'::uuid,
                jsonb_build_object(
                    'category_id', :'eventCategoryID',
                    'description', 'Learn the basics of Kubernetes deployment and management',
                    'kind_id', 'in-person',
                    'name', 'Kubernetes Fundamentals Workshop',
                    'timezone', 'America/New_York'
                )
            )
        )::jsonb - 'cohosts' - 'community' - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'slug' - 'ticket_types'
    )) = '{
        "attendee_count": 0,
        "canceled": false,
        "category_name": "Conference",
        "capacity": 500,
        "description": "Learn the basics of Kubernetes deployment and management",
        "event_reminder_enabled": true,
        "has_registration_questions": false,
        "has_related_events": false,
        "has_ticket_purchases": false,
        "hosts": [],
        "speakers": [],
        "kind": "in-person",
        "labels": [],
        "logo_url": "https://example.com/logo.png",
        "name": "Kubernetes Fundamentals Workshop",
        "published": false,
        "remaining_capacity": 500,
        "seller_display_name": "Add Event Fiscal Sponsor",
        "sponsors": [],
        "sessions": {},
        "test_event": false,
        "manual_tax_rate_ids": [],
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "automatic",
        "timezone": "America/New_York",
        "attendee_approval_required": false,
        "meeting_recording_published": false,
        "meeting_recording_requested": true,
        "registration_questions": [],
        "registration_questions_locked": false,
        "waitlist_count": 0,
        "waitlist_enabled": false
    }'::jsonb,
    'Should create event with minimal required fields and return expected structure'
);

-- Should create the default General Admission ticket type
select is(
    (
        select jsonb_build_object(
            'active', ett.active,
            'amount_minor', etpw.amount_minor,
            'availability', ett.availability,
            'order', ett."order",
            'seats_total', ett.seats_total,
            'title', ett.title
        )
        from event e
        join event_ticket_type ett using (event_id)
        join event_ticket_price_window etpw using (event_ticket_type_id)
        where e.name = 'Kubernetes Fundamentals Workshop'
    ),
    '{
        "active": true,
        "amount_minor": 0,
        "availability": "public",
        "order": 1,
        "seats_total": 500,
        "title": "General Admission"
    }'::jsonb,
    'Should create the default General Admission ticket type'
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
            select
                'event_added',
                null::uuid,
                null::text,
                %L::uuid,
                %L::uuid,
                event_id,
                'event',
                event_id
            from event
            where name = 'Kubernetes Fundamentals Workshop'
        $$,
        :'communityID',
        :'groupID'
    ),
    'Should create the expected audit row'
);

-- Should store the actor as the event creator
select add_event(
    :'user1ID'::uuid,
    :'groupID'::uuid,
    jsonb_build_object(
        'category_id', :'eventCategoryID',
        'description', 'Verifies creator tracking',
        'kind_id', 'in-person',
        'name', 'Created By Test',
        'timezone', 'America/New_York'
    )
) as "createdByEventID" \gset

select is(
    (
        select created_by
        from event
        where event_id = :'createdByEventID'::uuid
    ),
    :'user1ID'::uuid,
    'Should store the actor as the event creator'
);

-- Should snapshot accepted group team organizers only
select results_eq(
    $$
        select eo.user_id, eo."order"
        from event_organizer eo
        join event e using (event_id)
        where e.name = 'Kubernetes Fundamentals Workshop'
        order by eo.user_id
    $$,
    format(
        $$values (%L::uuid, 2), (%L::uuid, null::integer)$$,
        :'user1ID',
        :'user3ID'
    ),
    'Should snapshot accepted group team organizers and their order only'
);

-- Should store submitted organizers in submitted order
select add_event(
    null::uuid,
    :'groupID'::uuid,
    jsonb_build_object(
        'category_id', :'eventCategoryID',
        'description', 'Event with submitted organizers',
        'kind_id', 'virtual',
        'name', 'Submitted Organizers Event',
        'organizers', jsonb_build_array(:'user3ID', :'user1ID'),
        'timezone', 'UTC'
    )
) as "submittedOrganizersEventID" \gset

select results_eq(
    format(
        $$
            select user_id, "order"
            from event_organizer
            where event_id = %L::uuid
            order by "order"
        $$,
        :'submittedOrganizersEventID'
    ),
    format(
        $$values (%L::uuid, 1), (%L::uuid, 2)$$,
        :'user3ID',
        :'user1ID'
    ),
    'Should store submitted organizers in submitted order'
);

-- Should store no organizers when an empty list is submitted
select add_event(
    null::uuid,
    :'groupID'::uuid,
    jsonb_build_object(
        'category_id', :'eventCategoryID',
        'description', 'Event without organizers',
        'kind_id', 'virtual',
        'name', 'Empty Organizers Event',
        'organizers', '[]'::jsonb,
        'timezone', 'UTC'
    )
) as "emptyOrganizersEventID" \gset

select is(
    (select count(*)::int from event_organizer where event_id = :'emptyOrganizersEventID'::uuid),
    0,
    'Should store no organizers when an empty list is submitted'
);

-- Should reject an organizer outside the group team
select throws_ok(
    format(
        $$select add_event(null::uuid, %L::uuid, %L::jsonb)$$,
        :'groupID',
        jsonb_build_object(
            'category_id', :'eventCategoryID',
            'description', 'Event with an organizer outside the group team',
            'kind_id', 'virtual',
            'name', 'Outsider Organizer Event',
            'organizers', jsonb_build_array(:'user1ID', :'outsiderUserID'),
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'organizer is not a group team member',
    'Should reject an organizer outside the group team'
);

-- Should create event with all fields including hosts, sponsors, and sessions
with new_event as (
    select add_event(
        null::uuid,
        :'groupID'::uuid,
        format(
            '{
                "name": "CloudNativeCon Seattle 2025",
                "description": "Premier conference for cloud native technologies and community collaboration",
                "timezone": "America/Los_Angeles",
                "category_id": "%1$s",
                "kind_id": "hybrid",
                "banner_url": "https://example.com/banner.jpg",
                "capacity": 100,
                "description_short": "Short description",
                "starts_at": "2030-01-01T10:00:00",
                "ends_at": "2030-01-01T12:00:00",
                "logo_url": "https://example.com/logo.png",
                "luma_url": "https://luma.com/event",
                "meeting_hosts": ["host1@example.com", "host2@example.com"],
                "meeting_join_instructions": "Use the waiting room display name from your ticket.",
                "meeting_join_url": "https://youtube.com/live",
                "meeting_recording_url": "https://youtube.com/recording",
                "meetup_url": "https://meetup.com/event",
                "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
                "tags": ["technology", "conference", "networking"],
                "test_event": true,
                "venue_address": " 123 Main St ",
                "venue_city": " San Francisco ",
                "venue_country_code": " US ",
                "venue_country_name": " United States ",
                "venue_name": " Tech Center ",
                "venue_state_code": " ca ",
                "venue_state": " California ",
                "venue_zip_code": " 94105 ",
                "hosts": ["%2$s", "%3$s"],
                "speakers": [
                    {"user_id": "%3$s", "featured": true},
                    {"user_id": "%4$s", "featured": false}
                ],
                "sessions": [
                    {
                        "name": "Opening Keynote",
                        "description": "Welcome and introduction to the conference",
                        "starts_at": "2030-01-01T10:00:00",
                        "ends_at": "2030-01-01T10:45:00",
                        "kind": "in-person",
                        "location": "Main Hall",
                        "speakers": [{"user_id": "%4$s", "featured": true}]
                    },
                    {
                        "name": "Kubernetes Best Practices",
                        "description": "Deep dive into Kubernetes best practices",
                        "starts_at": "2030-01-01T11:00:00",
                        "ends_at": "2030-01-01T11:45:00",
                        "kind": "virtual",
                        "meeting_hosts": ["session-host@example.com"],
                        "meeting_join_instructions": "Use the session access code from your email.",
                        "meeting_join_url": "https://youtube.com/live/session2",
                        "speakers": [
                            {"user_id": "%2$s", "featured": false},
                            {"user_id": "%3$s", "featured": true}
                        ]
                    }
                ],
                "sponsors": [
                    {"group_sponsor_id": "%5$s", "level": "Gold"},
                    {"group_sponsor_id": "%6$s", "level": "Silver"}
                ]
            }',
            :'eventCategoryID',
            :'user1ID',
            :'user2ID',
            :'user3ID',
            :'sponsor1ID',
            :'sponsor2ID'
        )::jsonb
    ) as event_id
)
select event_id as "eventID" from new_event \gset

-- Check event fields except sessions
select ok(
    (select get_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid
    )::jsonb - 'cohosts' - 'community' - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'sessions' - 'slug' - 'ticket_types') = format('{
        "attendee_count": 0,
        "canceled": false,
        "category_name": "Conference",
        "description": "Premier conference for cloud native technologies and community collaboration",
        "hosts": [
            {"name": "Host One", "user_id": "%1$s", "username": "host1"},
            {"name": "Host Two", "user_id": "%2$s", "username": "host2"}
        ],
        "speakers": [
            {"name": "Host Two", "user_id": "%2$s", "username": "host2", "featured": true},
            {"name": "Speaker One", "user_id": "%3$s", "username": "speaker1", "featured": false}
        ],
        "kind": "hybrid",
        "labels": [],
        "name": "CloudNativeCon Seattle 2025",
        "published": false,
        "timezone": "America/Los_Angeles",
        "test_event": true,
        "attendee_approval_required": false,
        "banner_url": "https://example.com/banner.jpg",
        "capacity": 500,
        "remaining_capacity": 500,
        "seller_display_name": "Add Event Fiscal Sponsor",
        "description_short": "Short description",
        "event_reminder_enabled": true,
        "has_registration_questions": false,
        "has_related_events": false,
        "has_ticket_purchases": false,
        "starts_at": 1893520800,
        "ends_at": 1893528000,
        "logo_url": "https://example.com/logo.png",
        "luma_url": "https://luma.com/event",
        "meeting_hosts": ["host1@example.com", "host2@example.com"],
        "meeting_join_instructions": "Use the waiting room display name from your ticket.",
        "meeting_join_url": "https://youtube.com/live",
        "meeting_recording_published": false,
        "meeting_recording_requested": true,
        "meeting_recording_url": "https://youtube.com/recording",
        "meetup_url": "https://meetup.com/event",
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "registration_questions": [],
        "registration_questions_locked": false,
        "tags": ["technology", "conference", "networking"],
        "manual_tax_rate_ids": [],
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "automatic",
        "venue_address": "123 Main St",
        "venue_city": "San Francisco",
        "venue_country_code": "US",
        "venue_country_name": "United States",
        "venue_name": "Tech Center",
        "venue_state_code": "CA",
        "venue_state_name": "California",
        "venue_zip_code": "94105",
        "waitlist_count": 0,
        "waitlist_enabled": false,
        "sponsors": [
            {"group_sponsor_id": "%5$s", "level": "Silver", "logo_url": "https://example.com/cloudinc.png", "name": "CloudInc"},
            {"group_sponsor_id": "%4$s", "level": "Gold", "logo_url": "https://example.com/techcorp.png", "name": "TechCorp", "website_url": "https://techcorp.com"}
        ]
    }',
        :'user1ID',
        :'user2ID',
        :'user3ID',
        :'sponsor1ID',
        :'sponsor2ID'
    )::jsonb,
    'Should create event with all fields (excluding sessions)'
);


-- Sessions should contain expected rows (ignoring session_id)
select ok(
    (select (
        get_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventID'::uuid
        )::jsonb->'sessions'->'2030-01-01'
    ) @>
        format('[
            {
                "name": "Kubernetes Best Practices",
                "description": "Deep dive into Kubernetes best practices",
                "starts_at": 1893524400,
                "ends_at": 1893527100,
                "kind": "virtual",
                "meeting_hosts": ["session-host@example.com"],
                "meeting_join_instructions": "Use the session access code from your email.",
                "meeting_join_url": "https://youtube.com/live/session2",
                "speakers": [
                    {"name": "Host One", "user_id": "%1$s", "username": "host1", "featured": false},
                    {"name": "Host Two", "user_id": "%2$s", "username": "host2", "featured": true}
                ]
            },
            {
                "name": "Opening Keynote",
                "description": "Welcome and introduction to the conference",
                "starts_at": 1893520800,
                "ends_at": 1893523500,
                "kind": "in-person",
                "location": "Main Hall",
                "speakers": [
                    {"name": "Speaker One", "user_id": "%3$s", "username": "speaker1", "featured": true}
                ]
            }
        ]',
            :'user1ID',
            :'user2ID',
            :'user3ID'
        )::jsonb
    ),
    'Sessions contain expected rows (ignoring session_id)'
);

-- Should create labels and link sessions to labels from the same payload
with labels_event as (
    select add_event(
        null::uuid,
        :'groupID'::uuid,
        jsonb_build_object(
            'category_id', :'eventCategoryID',
            'description', 'Event with labels',
            'ends_at', '2030-01-10T12:00:00',
            'kind_id', 'virtual',
            'labels', jsonb_build_array(
                jsonb_build_object(
                    'color', '#FEE2E2',
                    'event_label_id', :'labelWebID',
                    'is_new', true,
                    'name', 'track / web'
                ),
                jsonb_build_object(
                    'color', '#DBEAFE',
                    'event_label_id', :'labelAiID',
                    'is_new', true,
                    'name', 'track / ai + ml'
                )
            ),
            'name', 'CloudNativeCon Labels Event',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'kind', 'virtual',
                    'label_ids', jsonb_build_array(:'labelWebID'),
                    'name', 'Labeled Session',
                    'starts_at', '2030-01-10T10:00:00'
                )
            ),
            'starts_at', '2030-01-10T10:00:00',
            'timezone', 'UTC'
        )
    ) as event_id
)
select event_id as "eventWithLabelsID" from labels_event \gset

-- Should persist labels with the supplied identifiers
select results_eq(
    format(
        $$
            select event_label_id, name, color
            from event_label
            where event_id = %L::uuid
            order by name
        $$,
        :'eventWithLabelsID'
    ),
    format(
        $$values (%L::uuid, %L::text, %L::text), (%L::uuid, %L::text, %L::text)$$,
        :'labelAiID', 'track / ai + ml', '#DBEAFE',
        :'labelWebID', 'track / web', '#FEE2E2'
    ),
    'Should persist labels with the supplied identifiers'
);

-- Should link sessions to labels created in the same payload
select results_eq(
    format(
        $$
            select sl.event_label_id
            from session_label sl
            join session s on s.session_id = sl.session_id
            where s.event_id = %L::uuid
        $$,
        :'eventWithLabelsID'
    ),
    format($$values (%L::uuid)$$, :'labelWebID'),
    'Should link sessions to labels created in the same payload'
);

-- Should return created labels in the event payload
select is(
    get_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventWithLabelsID'::uuid
    )::jsonb->'labels',
    jsonb_build_array(
        jsonb_build_object(
            'color', '#DBEAFE',
            'event_label_id', :'labelAiID',
            'name', 'track / ai + ml'
        ),
        jsonb_build_object(
            'color', '#FEE2E2',
            'event_label_id', :'labelWebID',
            'name', 'track / web'
        )
    ),
    'Should return created labels in the event payload'
);

-- Should create no labels when the labels key is absent
with unlabeled_event as (
    select add_event(
        null::uuid,
        :'groupID'::uuid,
        jsonb_build_object(
            'category_id', :'eventCategoryID',
            'description', 'Event without labels',
            'kind_id', 'virtual',
            'name', 'CloudNativeCon Unlabeled Event',
            'timezone', 'UTC'
        )
    ) as event_id
)
select event_id as "eventWithoutLabelsID" from unlabeled_event \gset

select is(
    (select count(*)::int from event_label where event_id = :'eventWithoutLabelsID'::uuid),
    0,
    'Should create no labels when the labels key is absent'
);

-- Should reject sessions using labels missing from the event
select throws_ok(
    format(
        $$select add_event(null::uuid, %L::uuid, %L::jsonb)$$,
        :'groupID',
        jsonb_build_object(
            'category_id', :'eventCategoryID',
            'description', 'Event whose session uses an unknown label',
            'kind_id', 'virtual',
            'labels', jsonb_build_array(
                jsonb_build_object(
                    'color', '#DBEAFE',
                    'event_label_id', :'labelFailedID',
                    'is_new', true,
                    'name', 'track / failed'
                )
            ),
            'name', 'CloudNativeCon Failed Labels Event',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'kind', 'virtual',
                    'label_ids', jsonb_build_array(:'labelMissingID'),
                    'name', 'Failed Labeled Session',
                    'starts_at', '2030-01-10T10:00:00'
                )
            ),
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'invalid event labels',
    'Should reject sessions using labels missing from the event'
);

-- Should throw error when labels contain duplicate names
select throws_ok(
    format(
        $$select add_event(null::uuid, %L::uuid, %L::jsonb)$$,
        :'groupID',
        jsonb_build_object(
            'category_id', :'eventCategoryID',
            'description', 'Event with duplicate labels',
            'kind_id', 'virtual',
            'labels', jsonb_build_array(
                jsonb_build_object(
                    'color', '#FEE2E2',
                    'event_label_id', :'labelDuplicate1ID',
                    'is_new', true,
                    'name', 'track / web'
                ),
                jsonb_build_object(
                    'color', '#DBEAFE',
                    'event_label_id', :'labelDuplicate2ID',
                    'is_new', true,
                    'name', 'track / web'
                )
            ),
            'name', 'CloudNativeCon Duplicate Labels Event',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'duplicate label names',
    'Should throw error when labels contain duplicate names'
);

-- Should set meeting flags consistently for events and sessions when requested
with request_event as (
    select add_event(
        null::uuid,
        :'groupID'::uuid,
        format(
            '{
                "name": "Meeting Requested Event",
                "description": "Event requesting meeting support",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "virtual",
                "capacity": 100,
                "starts_at": "2030-03-01T10:00:00",
                "ends_at": "2030-03-01T11:30:00",
                "meeting_hosts": ["event-alt-host@example.com"],
                "meeting_provider_id": "zoom",
                "meeting_requested": true,
                "sessions": [
                    {
                        "name": "Requested Session",
                        "description": "Session needing meeting",
                        "starts_at": "2030-03-01T10:00:00",
                        "ends_at": "2030-03-01T11:00:00",
                        "kind": "virtual",
                        "meeting_hosts": ["session-alt-host@example.com"],
                        "meeting_provider_id": "zoom",
                        "meeting_requested": true
                    }
                ]
            }',
            :'eventCategoryID'
        )::jsonb
    ) as event_id
)
select event_id as "eventRequestID" from request_event \gset
select is(
    (
        select jsonb_build_object(
            'event', jsonb_build_object(
                'meeting_hosts', meeting_hosts,
                'meeting_recording_published', meeting_recording_published,
                'meeting_recording_requested', meeting_recording_requested,
                'meeting_requested', meeting_requested,
                'meeting_in_sync', meeting_in_sync
            ),
            'session', (
                select jsonb_build_object(
                    'meeting_hosts', meeting_hosts,
                    'meeting_recording_published', meeting_recording_published,
                    'meeting_requested', meeting_requested,
                    'meeting_in_sync', meeting_in_sync
                )
                from session
                where event_id = :'eventRequestID'::uuid
            )
        )
        from event
        where event_id = :'eventRequestID'::uuid
    ),
    '{
        "event": {
            "meeting_hosts": ["event-alt-host@example.com"],
            "meeting_recording_published": false,
            "meeting_recording_requested": true,
            "meeting_requested": true,
            "meeting_in_sync": false
        },
        "session": {
            "meeting_hosts": ["session-alt-host@example.com"],
            "meeting_recording_published": false,
            "meeting_requested": true,
            "meeting_in_sync": false
        }
    }'::jsonb,
    'Should set meeting flags and hosts for event and session when requested'
);

-- Should persist explicit event meeting recording preference
select add_event(
    null::uuid,
    :'groupID'::uuid,
    format(
        '{
            "name": "Meeting Recording Disabled Event",
            "description": "Event requesting meeting support without recording",
            "timezone": "UTC",
            "category_id": "%s",
            "kind_id": "virtual",
            "capacity": 100,
            "starts_at": "2030-03-02T10:00:00",
            "ends_at": "2030-03-02T11:30:00",
            "meeting_provider_id": "zoom",
            "meeting_recording_published": false,
            "meeting_recording_requested": false,
            "meeting_requested": true
        }',
        :'eventCategoryID'
    )::jsonb
) as "recordingDisabledEventID" \gset
select is(
    (select meeting_recording_published from event where event_id = :'recordingDisabledEventID'::uuid),
    false,
    'Should persist event meeting recording visibility when unpublished'
);
select is(
    (select meeting_recording_requested from event where event_id = :'recordingDisabledEventID'::uuid),
    false,
    'Should persist event meeting recording preference when disabled'
);

-- Should create event with registration window dates
select add_event(
    null::uuid,
    :'groupID'::uuid,
    jsonb_build_object(
        'name', 'Registration Window Event',
        'description', 'Event with configured registration dates',
        'timezone', 'UTC',
        'category_id', :'eventCategoryID',
        'kind_id', 'in-person',
        'starts_at', '2030-02-01T12:00:00',
        'ends_at', '2030-02-01T14:00:00',
        'registration_starts_at', '2030-02-01T09:00:00',
        'registration_ends_at', '2030-02-01T11:00:00'
    )
) as "registrationWindowEventID" \gset
select is(
    (
        select jsonb_build_object(
            'registration_ends_at', floor(extract(epoch from registration_ends_at)),
            'registration_starts_at', floor(extract(epoch from registration_starts_at))
        )
        from event
        where event_id = :'registrationWindowEventID'::uuid
    ),
    jsonb_build_object(
        'registration_ends_at', floor(extract(epoch from '2030-02-01 11:00:00+00'::timestamptz)),
        'registration_starts_at', floor(extract(epoch from '2030-02-01 09:00:00+00'::timestamptz))
    ),
    'Should persist registration window dates when creating an event'
);

-- Should reject the default tier above max participants
select throws_ok(
    format(
        $$select add_event(null::uuid, %L::uuid, %L::jsonb, %L::jsonb)$$,
        :'groupID',
        jsonb_build_object(
            'category_id', :'eventCategoryID',
            'description', 'Test',
            'ends_at', '2030-03-01T11:00:00',
            'kind_id', 'virtual',
            'meeting_provider_id', 'zoom',
            'meeting_requested', true,
            'name', 'Capacity Exceed Event',
            'starts_at', '2030-03-01T10:00:00',
            'timezone', 'UTC'
        ),
        '{"zoom": {"max_duration_minutes": 720, "max_participants": 100, "min_duration_minutes": 5}}'
    ),
    'OCG01',
    'event capacity (500) exceeds maximum participants allowed (100)',
    'Should reject the default tier above max participants'
);

-- Should reject ticket-derived capacity above the meeting provider limit
select throws_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{
                "name": "Ticketed Capacity Exceed Event",
                "description": "Test",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "virtual",
                "capacity": 10,
                "meeting_requested": true,
                "meeting_provider_id": "zoom",
                "starts_at": "2030-03-01T10:00:00",
                "ends_at": "2030-03-01T11:00:00",
                "ticket_types": [
                    {
                        "active": true,
                        "event_ticket_type_id": "3a020000-0000-0000-0000-000000000092",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 0,
                                "event_ticket_price_window_id": "3a020000-0000-0000-0000-000000000093"
                            }
                        ],
                        "seats_total": 150,
                        "title": "General"
                    }
                ]
            }'::jsonb,
            '{"zoom": {"max_duration_minutes": 720, "max_participants": 100, "min_duration_minutes": 5}}'::jsonb,
            'stripe'
        )$$,
        :'groupID',
        :'eventCategoryID'
    ),
    'OCG01',
    'event capacity (150) exceeds maximum participants allowed (100)',
    'Should reject ticket-derived capacity above the meeting provider limit'
);

-- Should reject an event meeting longer than the provider maximum duration
select throws_ok(
    format(
        $$select add_event(null::uuid, %L::uuid, %L::jsonb, %L::jsonb)$$,
        :'groupID',
        jsonb_build_object(
            'category_id', :'eventCategoryID',
            'description', 'Test',
            'ends_at', '2030-03-01T22:01:00',
            'kind_id', 'virtual',
            'meeting_provider_id', 'zoom',
            'meeting_requested', true,
            'name', 'Long Meeting Event',
            'starts_at', '2030-03-01T10:00:00',
            'timezone', 'UTC'
        ),
        '{"zoom": {"max_duration_minutes": 720, "max_participants": 500, "min_duration_minutes": 5}}'
    ),
    'OCG01',
    'event meeting duration (721 minutes) must be between 5 and 720 minutes',
    'Should reject an event meeting longer than the provider maximum duration'
);

-- Should create a paid-capable hybrid event with a complete physical venue
select add_event(
    null::uuid,
    :'groupID'::uuid,
    format(
        '{
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_add_event",
                    "seller_display_name": "Add Event Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_add_event",
                    "seller_display_name": "Add Event Fiscal Sponsor"
                }
            },
            "name": "Paid Hybrid Event",
            "description": "Test",
            "timezone": "UTC",
            "category_id": "%s",
            "kind_id": "hybrid",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a020000-0000-0000-0000-000000000097",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a020000-0000-0000-0000-000000000098"
                        }
                    ],
                    "seats_total": 25,
                    "title": "Hybrid admission"
                }
            ],
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_country_name": "United States",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105"
        }',
        :'eventCategoryID'
    )::jsonb,
    null::jsonb,
    'stripe'
) as "paidHybridEventID" \gset

select is(
    (
        select jsonb_build_object(
            'amount_minor', etpw.amount_minor,
            'event_kind_id', e.event_kind_id,
            'payment_currency_code', e.payment_currency_code,
            'venue_address', e.venue_address,
            'venue_city', e.venue_city,
            'venue_country_code', e.venue_country_code,
            'venue_country_name', e.venue_country_name,
            'venue_name', e.venue_name,
            'venue_state_code', e.venue_state_code,
            'venue_state_name', e.venue_state_name,
            'venue_zip_code', e.venue_zip_code
        )
        from event e
        join event_ticket_type ett using (event_id)
        join event_ticket_price_window etpw using (event_ticket_type_id)
        where e.event_id = :'paidHybridEventID'::uuid
    ),
    '{
        "amount_minor": 2500,
        "event_kind_id": "hybrid",
        "payment_currency_code": "USD",
        "venue_address": "123 Main St",
        "venue_city": "San Francisco",
        "venue_country_code": "US",
        "venue_country_name": "United States",
        "venue_name": "Community Hall",
        "venue_state_code": "CA",
        "venue_state_name": "California",
        "venue_zip_code": "94105"
    }'::jsonb,
    'Should persist paid hybrid ticketing and its complete physical venue'
);

-- Should create an all-zero ticketed event without payment configuration
select lives_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{
                "name": "Free Ticket Event",
                "description": "Test",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "ticket_types": [
                    {
                        "active": true,
                        "event_ticket_type_id": "3a020000-0000-0000-0000-000000000095",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 0,
                                "event_ticket_price_window_id": "3a020000-0000-0000-0000-000000000096"
                            }
                        ],
                        "seats_total": 25,
                        "title": "Free admission"
                    }
                ]
            }'::jsonb
        )$$,
        :'groupID',
        :'eventCategoryID'
    ),
    'Should create an all-zero ticketed event without payment configuration'
);

-- Should reject approval-required events when waitlist is enabled
select throws_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{
                "name": "Approval Waitlist Event",
                "description": "Test",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "attendee_approval_required": true,
                "capacity": 100,
                "waitlist_enabled": true
            }'::jsonb
        )$$,
        :'groupID',
        :'eventCategoryID'
    ),
    'OCG01',
    'approval-required events cannot enable waitlist',
    'Should reject approval-required events when waitlist is enabled'
);

-- Should throw error when discount codes are provided without ticket types
select throws_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{
                "name": "Discounts Without Tickets",
                "description": "Test",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "discount_codes": [
                    {
                        "active": true,
                        "amount_minor": 500,
                        "code": "SAVE20",
                        "event_discount_code_id": "3a020000-0000-0000-0000-000000000091",
                        "kind": "fixed_amount",
                        "title": "Launch"
                    }
                ]
            }'::jsonb
        )$$,
        :'groupID',
        :'eventCategoryID'
    ),
    'OCG01',
    'discount_codes require positive ticket pricing',
    'Should throw error when discount codes are provided without ticket types'
);

-- Should throw error when payment currency is provided without ticket types
select throws_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{
                "name": "Currency Without Tickets",
                "description": "Test",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "payment_currency_code": "USD"
            }'::jsonb
        )$$,
        :'groupID',
        :'eventCategoryID'
    ),
    'OCG01',
    'payment_currency_code requires positive ticket pricing',
    'Should throw error when payment currency is provided without ticket types'
);

-- Should throw error when ticket types are missing stable identifiers
select throws_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{
                "name": "Ticket Type Without Identifier",
                "description": "Test",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "payment_currency_code": "USD",
                "ticket_types": [
                    {
                        "active": true,
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 2500,
                                "event_ticket_price_window_id": "3a020000-0000-0000-0000-000000000094"
                            }
                        ],
                        "seats_total": 25,
                        "title": "General"
                    }
                ]
            }'::jsonb
        )$$,
        :'groupID',
        :'eventCategoryID'
    ),
    'OCG01',
    'ticket types require event_ticket_type_id',
    'Should throw error when ticket types omit stable identifiers'
);

-- Should throw error when event starts_at is in the past
select throws_ok(
    format(
        $$select add_event(null::uuid, %L::uuid, %L::jsonb)$$,
        :'groupID',
        jsonb_build_object(
            'category_id', :'eventCategoryID',
            'description', 'Test',
            'kind_id', 'in-person',
            'name', 'Past Event',
            'starts_at', '2020-01-01T10:00:00',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'event starts_at cannot be in the past',
    'Should throw error when event starts_at is in the past'
);

-- Should throw error when session starts_at is before event starts_at
select throws_ok(
    format(
        $$select add_event(null::uuid, %L::uuid, %L::jsonb)$$,
        :'groupID',
        jsonb_build_object(
            'category_id', :'eventCategoryID',
            'description', 'Test',
            'ends_at', '2030-01-01T12:00:00',
            'kind_id', 'in-person',
            'name', 'Session Before Event',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'ends_at', '2030-01-01T10:30:00',
                    'kind', 'in-person',
                    'name', 'Early Session',
                    'starts_at', '2030-01-01T09:00:00'
                )
            ),
            'starts_at', '2030-01-01T10:00:00',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'session starts_at must be within event bounds',
    'Should throw error when session starts_at is before event starts_at'
);

-- Should store registration questions when creating an event
select add_event(
    null::uuid,
    :'groupID'::uuid,
    format('{"name": "Event With Questions", "description": "Test", "timezone": "UTC", "category_id": "%s", "kind_id": "in-person", "registration_questions": [{"id": "3a020000-0000-0000-0000-000000000501", "kind": "single-select", "prompt": "Meal preference", "required": true, "options": [{"id": "3a020000-0000-0000-0000-000000000601", "label": "Standard"}, {"id": "3a020000-0000-0000-0000-000000000602", "label": "Vegetarian"}]}]}', :'eventCategoryID')::jsonb
) as "questionsEventID" \gset

select is(
    (
        select registration_questions
        from event
        where event_id = :'questionsEventID'::uuid
    ),
    '[{"id": "3a020000-0000-0000-0000-000000000501", "kind": "single-select", "prompt": "Meal preference", "required": true, "options": [{"id": "3a020000-0000-0000-0000-000000000601", "label": "Standard"}, {"id": "3a020000-0000-0000-0000-000000000602", "label": "Vegetarian"}]}]'::jsonb,
    'Should store registration questions when creating an event'
);

-- Should validate registration questions when creating an event
select throws_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{"name": "Event With Invalid Questions", "description": "Test", "timezone": "UTC", "category_id": "%s", "kind_id": "in-person", "registration_questions": [{"id": "bad", "kind": "free-text", "prompt": "Question", "required": true, "options": []}]}'::jsonb
        )$$,
        :'groupID',
        :'eventCategoryID'
    ),
    'OCG01',
    'questionnaire question id must be a uuid',
    'Should validate registration questions when creating an event'
);

-- Should reject a submitted external URL when the group cannot collect externally
select throws_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{
                "name": "Rejected External Fields Event",
                "description": "Test",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "external_payment_instructions": "Pay offline",
                "external_payment_url": "https://pay.example.test/ignored",
                "external_payment_window_hours": 48,
                "payment_currency_code": "USD",
                "ticket_types": [
                    {
                        "active": true,
                        "event_ticket_type_id": "3a020000-0000-0000-0000-0000000000a1",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 2500,
                                "event_ticket_price_window_id": "3a020000-0000-0000-0000-0000000000a2"
                            }
                        ],
                        "seats_total": 25,
                        "title": "General admission"
                    }
                ],
                "venue_address": "123 Main St",
                "venue_city": "San Francisco",
                "venue_country_code": "US",
                "venue_name": "Community Hall",
                "venue_zip_code": "94105"
            }'::jsonb,
            null::jsonb,
            'stripe'
        )$$,
        :'groupID',
        :'eventCategoryID'
    ),
    'OCG01',
    'external payments are not available for this event',
    'Should reject a submitted external URL when the group cannot collect externally'
);

-- Should create a paid external event with a valid payment URL
select add_event(
    null::uuid,
    :'groupExternalID'::uuid,
    format(
        '{
            "name": "Paid External Event",
            "description": "Test",
            "timezone": "UTC",
            "category_id": "%s",
            "kind_id": "in-person",
            "external_payment_instructions": "Transfer to the organizer account",
            "external_payment_url": "https://pay.example.test/add",
            "external_payment_window_hours": 96,
            "payment_currency_code": "KRW",
            "tax_behavior": "exclusive",
            "tax_calculation_mode": "automatic",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a020000-0000-0000-0000-0000000000a3",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 5000,
                            "event_ticket_price_window_id": "3a020000-0000-0000-0000-0000000000a4"
                        }
                    ],
                    "seats_total": 25,
                    "title": "General admission"
                }
            ],
            "venue_address": "1 Test Street",
            "venue_city": "Seoul",
            "venue_country_code": "KR",
            "venue_name": "Test Hall",
            "venue_zip_code": "00000"
        }',
        :'eventCategoryID'
    )::jsonb,
    null::jsonb,
    null
) as "paidExternalEventID" \gset

select is(
    (
        select jsonb_build_object(
            'external_payment_instructions', e.external_payment_instructions,
            'external_payment_url', e.external_payment_url,
            'external_payment_window_hours', e.external_payment_window_hours,
            'tax_behavior', e.tax_behavior,
            'tax_calculation_mode', e.tax_calculation_mode
        )
        from event e
        where e.event_id = :'paidExternalEventID'::uuid
    ),
    '{
        "external_payment_instructions": "Transfer to the organizer account",
        "external_payment_url": "https://pay.example.test/add",
        "external_payment_window_hours": 96,
        "tax_behavior": "inclusive",
        "tax_calculation_mode": "none"
    }'::jsonb,
    'Should create a paid external event with a valid payment URL'
);

-- Should persist a null external window so checkout can apply the config default
select add_event(
    null::uuid,
    :'groupExternalID'::uuid,
    format(
        '{
            "name": "External Default Window Event",
            "description": "Test",
            "timezone": "UTC",
            "category_id": "%s",
            "kind_id": "in-person",
            "external_payment_url": "https://pay.example.test/default-window",
            "payment_currency_code": "KRW",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a020000-0000-0000-0000-0000000000a5",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 5000,
                            "event_ticket_price_window_id": "3a020000-0000-0000-0000-0000000000a6"
                        }
                    ],
                    "seats_total": 25,
                    "title": "General admission"
                }
            ],
            "venue_address": "1 Test Street",
            "venue_city": "Seoul",
            "venue_country_code": "KR",
            "venue_name": "Test Hall",
            "venue_zip_code": "00000"
        }',
        :'eventCategoryID'
    )::jsonb,
    null::jsonb,
    null
) as "externalDefaultWindowEventID" \gset

select is(
    (
        select external_payment_window_hours
        from event
        where event_id = :'externalDefaultWindowEventID'::uuid
    ),
    null::int,
    'Should persist a null external window so checkout can apply the config default'
);

-- Should reject a paid external event without a payment URL
select throws_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{
                "name": "Missing External URL Event",
                "description": "Test",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "payment_currency_code": "KRW",
                "ticket_types": [
                    {
                        "active": true,
                        "event_ticket_type_id": "3a020000-0000-0000-0000-0000000000a7",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 5000,
                                "event_ticket_price_window_id": "3a020000-0000-0000-0000-0000000000a8"
                            }
                        ],
                        "seats_total": 25,
                        "title": "General admission"
                    }
                ],
                "venue_address": "1 Test Street",
                "venue_city": "Seoul",
                "venue_country_code": "KR",
                "venue_name": "Test Hall",
                "venue_zip_code": "00000"
            }'::jsonb,
            null::jsonb,
            null
        )$$,
        :'groupExternalID',
        :'eventCategoryID'
    ),
    'OCG01',
    'paid-capable events require a valid external payment url',
    'Should reject a paid external event without a payment URL'
);

-- Should reject a paid event on Stripe while the selected external rail lacks its payee name
select throws_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{
                "name": "Nameless External Group Event",
                "description": "Test",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "payment_currency_code": "KRW",
                "ticket_types": [
                    {
                        "active": true,
                        "event_ticket_type_id": "3a020000-0000-0000-0000-0000000000b2",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 5000,
                                "event_ticket_price_window_id": "3a020000-0000-0000-0000-0000000000b3"
                            }
                        ],
                        "seats_total": 25,
                        "title": "General admission"
                    }
                ],
                "venue_address": "1 Test Street",
                "venue_city": "Seoul",
                "venue_country_code": "KR",
                "venue_name": "Test Hall",
                "venue_zip_code": "00000"
            }'::jsonb,
            null::jsonb,
            null
        )$$,
        :'groupExternalNamelessID',
        :'eventCategoryID'
    ),
    'OCG01',
    'external payments require the legal name of the organization collecting payments',
    'Should reject a paid event on Stripe while the selected external rail lacks its payee name'
);

-- Should reject a paid external event with a venue outside the group country
select throws_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{
                "name": "External Abroad Event",
                "description": "Test",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "external_payment_url": "https://pay.example.test/abroad",
                "payment_currency_code": "KRW",
                "ticket_types": [
                    {
                        "active": true,
                        "event_ticket_type_id": "3a020000-0000-0000-0000-0000000000af",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 5000,
                                "event_ticket_price_window_id": "3a020000-0000-0000-0000-0000000000b0"
                            }
                        ],
                        "seats_total": 25,
                        "title": "General admission"
                    }
                ],
                "venue_address": "1 Test Street",
                "venue_city": "Tokyo",
                "venue_country_code": "JP",
                "venue_name": "Test Hall",
                "venue_zip_code": "100-0001"
            }'::jsonb,
            null::jsonb,
            null
        )$$,
        :'groupExternalID',
        :'eventCategoryID'
    ),
    'OCG01',
    'external paid events require a venue in the group country',
    'Should reject a paid external event with a venue outside the group country'
);

-- Should reject an external payment window above the configured maximum
select throws_ok(
    format(
        $$select add_event(
            null::uuid,
            %L::uuid,
            '{
                "name": "External Window Too Large Event",
                "description": "Test",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "external_payment_url": "https://pay.example.test/too-large",
                "external_payment_window_hours": 337,
                "payment_currency_code": "KRW",
                "ticket_types": [
                    {
                        "active": true,
                        "event_ticket_type_id": "3a020000-0000-0000-0000-0000000000ab",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 5000,
                                "event_ticket_price_window_id": "3a020000-0000-0000-0000-0000000000ac"
                            }
                        ],
                        "seats_total": 25,
                        "title": "General admission"
                    }
                ],
                "venue_address": "1 Test Street",
                "venue_city": "Seoul",
                "venue_country_code": "KR",
                "venue_name": "Test Hall",
                "venue_zip_code": "00000"
            }'::jsonb,
            null::jsonb,
            null
        )$$,
        :'groupExternalID',
        :'eventCategoryID'
    ),
    'OCG01',
    'external payment window exceeds the configured maximum',
    'Should reject an external payment window above the configured maximum'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
