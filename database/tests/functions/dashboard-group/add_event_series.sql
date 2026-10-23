-- Tests adding recurring event series.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(22);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a030000-0000-0000-0000-000000000001'
\set eventCategoryID '3a030000-0000-0000-0000-000000000002'
\set groupCategoryID '3a030000-0000-0000-0000-000000000003'
\set groupID '3a030000-0000-0000-0000-000000000004'
\set labelOccurrence1ID '3a030000-0000-0000-0000-000000000006'
\set labelOccurrence2ID '3a030000-0000-0000-0000-000000000007'
\set secondTeamMemberID '3a030000-0000-0000-0000-000000000008'
\set teamMemberID '3a030000-0000-0000-0000-000000000009'
\set userID '3a030000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the series group
select fx_community(:'communityID');

-- Second accepted group team member snapshotted as an organizer
select fx_user(:'secondTeamMemberID');

-- First accepted group team member snapshotted as an organizer
select fx_user(:'teamMemberID');

-- Actor creating the series
select fx_user(:'userID');

-- Event category used by the series events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the series group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the series
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Accepted group team used as the default organizers
insert into group_team (accepted, group_id, role, user_id, "order")
values
    (true, :'groupID', 'viewer', :'secondTeamMemberID', 2),
    (true, :'groupID', 'viewer', :'teamMemberID', 1);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create all recurring events in one linked series
select lives_ok(
    format(
        $$
        select add_event_series(
            %L::uuid,
            %L::uuid,
            '[
                {
                    "name": "Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-01-07T10:00:00",
                    "ends_at": "2030-01-07T11:00:00"
                },
                {
                    "name": "Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-01-14T10:00:00",
                    "ends_at": "2030-01-14T11:00:00"
                }
            ]'::jsonb,
            '{"additional_occurrences": 1, "pattern": "weekly"}'::jsonb
        )
        $$,
        :'userID', :'groupID', :'eventCategoryID', :'eventCategoryID'
    ),
    'Should create all recurring events in one linked series'
);

-- Should create the expected number of events
select is(
    (select count(*)::int from event where name = 'Weekly Study Group'),
    2,
    'Should create the expected number of events'
);

-- Should give each occurrence its own labels and session links
select lives_ok(
    format(
        $$select add_event_series(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)$$,
        :'userID',
        :'groupID',
        jsonb_build_array(
                jsonb_build_object(
                    'category_id', :'eventCategoryID',
                    'description', 'Labeled base event',
                    'ends_at', '2030-01-07T11:00:00',
                    'kind_id', 'virtual',
                    'labels', jsonb_build_array(
                        jsonb_build_object(
                            'color', '#DBEAFE',
                            'event_label_id', :'labelOccurrence1ID',
                            'is_new', true,
                            'name', 'track / web'
                        )
                    ),
                    'name', 'Labeled Study Group',
                    'sessions', jsonb_build_array(
                        jsonb_build_object(
                            'kind', 'virtual',
                            'label_ids', jsonb_build_array(:'labelOccurrence1ID'),
                            'name', 'Labeled Session',
                            'starts_at', '2030-01-07T10:00:00'
                        )
                    ),
                    'starts_at', '2030-01-07T10:00:00',
                    'timezone', 'UTC'
                ),
                jsonb_build_object(
                    'category_id', :'eventCategoryID',
                    'description', 'Labeled base event',
                    'ends_at', '2030-01-14T11:00:00',
                    'kind_id', 'virtual',
                    'labels', jsonb_build_array(
                        jsonb_build_object(
                            'color', '#DBEAFE',
                            'event_label_id', :'labelOccurrence2ID',
                            'is_new', true,
                            'name', 'track / web'
                        )
                    ),
                    'name', 'Labeled Study Group',
                    'sessions', jsonb_build_array(
                        jsonb_build_object(
                            'kind', 'virtual',
                            'label_ids', jsonb_build_array(:'labelOccurrence2ID'),
                            'name', 'Labeled Session',
                            'starts_at', '2030-01-14T10:00:00'
                        )
                    ),
                    'starts_at', '2030-01-14T10:00:00',
                    'timezone', 'UTC'
                )
        ),
        '{"additional_occurrences": 1, "pattern": "weekly"}'::jsonb
    ),
    'Should give each occurrence its own labels and session links'
);
select results_eq(
    $$
        select e.starts_at, el.event_label_id, el.name
        from event_label el
        join event e on e.event_id = el.event_id
        where e.name = 'Labeled Study Group'
        order by e.starts_at
    $$,
    format(
        $$
            values
                ('2030-01-07 10:00:00+00'::timestamptz, %L::uuid, 'track / web'::text),
                ('2030-01-14 10:00:00+00'::timestamptz, %L::uuid, 'track / web'::text)
        $$,
        :'labelOccurrence1ID',
        :'labelOccurrence2ID'
    ),
    'Should store the labels of each occurrence on its own event'
);
select results_eq(
    $$
        select e.starts_at, sl.event_label_id
        from session_label sl
        join session s on s.session_id = sl.session_id
        join event e on e.event_id = s.event_id
        where e.name = 'Labeled Study Group'
        order by e.starts_at
    $$,
    format(
        $$
            values
                ('2030-01-07 10:00:00+00'::timestamptz, %L::uuid),
                ('2030-01-14 10:00:00+00'::timestamptz, %L::uuid)
        $$,
        :'labelOccurrence1ID',
        :'labelOccurrence2ID'
    ),
    'Should link each occurrence session to its own event labels'
);

-- Should link all created events to one series
select is(
    (
        select count(distinct event_series_id)::int
        from event
        where name = 'Weekly Study Group'
        and event_series_id is not null
    ),
    1,
    'Should link all created events to one series'
);

-- Should store recurrence metadata for the series
select results_eq(
    $$
        select
            recurrence_additional_occurrences,
            recurrence_pattern,
            timezone
        from event_series
        where event_series_id = (
            select distinct event_series_id
            from event
            where name = 'Weekly Study Group'
        )
    $$,
    $$
        values (1, 'weekly'::text, 'UTC'::text)
    $$,
    'Should store recurrence metadata for the series'
);

-- Should reject paid recurring events when payment readiness fails
select throws_ok(
    format(
        $$
        select add_event_series(
            %L::uuid,
            %L::uuid,
            '[
                {
                    "name": "Paid Weekly Study Group",
                    "description": "Base event",
                    "_payment_validation": {
                        "expected_payment_recipient": null,
                        "require_automatic_tax": true,
                        "validated_payment_recipient": null
                    },
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "payment_currency_code": "USD",
                    "starts_at": "2030-01-21T10:00:00",
                    "ends_at": "2030-01-21T11:00:00",
                    "ticket_types": [
                        {
                            "active": true,
                            "event_ticket_type_id": "3a030000-0000-0000-0000-000000000006",
                            "order": 1,
                            "price_windows": [
                                {
                                    "amount_minor": 2500,
                                    "event_ticket_price_window_id": "3a030000-0000-0000-0000-000000000007"
                                }
                            ],
                            "seats_total": 25,
                            "title": "Paid admission"
                        }
                    ]
                },
                {
                    "name": "Paid Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "payment_currency_code": "USD",
                    "starts_at": "2030-01-28T10:00:00",
                    "ends_at": "2030-01-28T11:00:00",
                    "ticket_types": [
                        {
                            "active": true,
                            "event_ticket_type_id": "3a030000-0000-0000-0000-000000000008",
                            "order": 1,
                            "price_windows": [
                                {
                                    "amount_minor": 2500,
                                    "event_ticket_price_window_id": "3a030000-0000-0000-0000-000000000009"
                                }
                            ],
                            "seats_total": 25,
                            "title": "Paid admission"
                        }
                    ]
                }
            ]'::jsonb,
            '{"additional_occurrences": 1, "pattern": "weekly"}'::jsonb,
            null,
            'stripe'
        )
        $$,
        :'userID', :'groupID', :'eventCategoryID', :'eventCategoryID'
    ),
    'OCG01',
    'paid-capable events require a payment recipient',
    'Should reject paid recurring events when payment readiness fails'
);

-- Should reject too few event payloads
select throws_ok(
    format(
        $$
        select add_event_series(
            %L::uuid,
            %L::uuid,
            '[
                {
                    "name": "Invalid Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-02-07T10:00:00"
                }
            ]'::jsonb,
            '{"additional_occurrences": 1, "pattern": "weekly"}'::jsonb
        )
        $$,
        :'userID', :'groupID', :'eventCategoryID'
    ),
    'OCG01',
    'events must include between 2 and 13 items',
    'Should reject too few event payloads'
);

-- Should reject too many event payloads
select throws_ok(
    format(
        $$
        select add_event_series(
            %L::uuid,
            %L::uuid,
            (
                select jsonb_agg(jsonb_build_object(
                    'name', 'Too Many Weekly Study Group',
                    'description', 'Base event',
                    'timezone', 'UTC',
                    'category_id', %L,
                    'kind_id', 'virtual',
                    'starts_at', format('2030-03-%%sT10:00:00', lpad(day::text, 2, '0')),
                    'ends_at', format('2030-03-%%sT11:00:00', lpad(day::text, 2, '0'))
                ))
                from generate_series(1, 14) as days(day)
            ),
            '{"additional_occurrences": 13, "pattern": "weekly"}'::jsonb
        )
        $$,
        :'userID', :'groupID', :'eventCategoryID'
    ),
    'OCG01',
    'events must include between 2 and 13 items',
    'Should reject too many event payloads'
);

-- Should reject invalid additional occurrence count
select throws_ok(
    format(
        $$
        select add_event_series(
            %L::uuid,
            %L::uuid,
            '[
                {
                    "name": "Invalid Count Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-04-07T10:00:00",
                    "ends_at": "2030-04-07T11:00:00"
                },
                {
                    "name": "Invalid Count Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-04-14T10:00:00",
                    "ends_at": "2030-04-14T11:00:00"
                }
            ]'::jsonb,
            '{"additional_occurrences": 0, "pattern": "weekly"}'::jsonb
        )
        $$,
        :'userID', :'groupID', :'eventCategoryID', :'eventCategoryID'
    ),
    'OCG01',
    'additional_occurrences must be between 1 and 12',
    'Should reject invalid additional occurrence count'
);

-- Should reject mismatched event and recurrence counts
select throws_ok(
    format(
        $$
        select add_event_series(
            %L::uuid,
            %L::uuid,
            '[
                {
                    "name": "Mismatched Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-05-07T10:00:00",
                    "ends_at": "2030-05-07T11:00:00"
                },
                {
                    "name": "Mismatched Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-05-14T10:00:00",
                    "ends_at": "2030-05-14T11:00:00"
                }
            ]'::jsonb,
            '{"additional_occurrences": 2, "pattern": "weekly"}'::jsonb
        )
        $$,
        :'userID', :'groupID', :'eventCategoryID', :'eventCategoryID'
    ),
    'OCG01',
    'events count must match additional_occurrences',
    'Should reject mismatched event and recurrence counts'
);

-- Should reject unsupported recurrence pattern
select throws_ok(
    format(
        $$
        select add_event_series(
            %L::uuid,
            %L::uuid,
            '[
                {
                    "name": "Unsupported Daily Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-06-07T10:00:00",
                    "ends_at": "2030-06-07T11:00:00"
                },
                {
                    "name": "Unsupported Daily Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-06-08T10:00:00",
                    "ends_at": "2030-06-08T11:00:00"
                }
            ]'::jsonb,
            '{"additional_occurrences": 1, "pattern": "daily"}'::jsonb
        )
        $$,
        :'userID', :'groupID', :'eventCategoryID', :'eventCategoryID'
    ),
    'OCG01',
    'unsupported recurrence pattern',
    'Should reject unsupported recurrence pattern'
);

-- Should reject missing timezone on the anchor event
select throws_ok(
    format(
        $$
        select add_event_series(
            %L::uuid,
            %L::uuid,
            '[
                {
                    "name": "Missing Timezone Weekly Study Group",
                    "description": "Base event",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-07-07T10:00:00",
                    "ends_at": "2030-07-07T11:00:00"
                },
                {
                    "name": "Missing Timezone Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-07-14T10:00:00",
                    "ends_at": "2030-07-14T11:00:00"
                }
            ]'::jsonb,
            '{"additional_occurrences": 1, "pattern": "weekly"}'::jsonb
        )
        $$,
        :'userID', :'groupID', :'eventCategoryID', :'eventCategoryID'
    ),
    'OCG01',
    'recurring events require timezone',
    'Should reject missing timezone on the anchor event'
);

-- Should reject missing start date on the anchor event
select throws_ok(
    format(
        $$
        select add_event_series(
            %L::uuid,
            %L::uuid,
            '[
                {
                    "name": "Missing Start Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "ends_at": "2030-08-07T11:00:00"
                },
                {
                    "name": "Missing Start Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-08-14T10:00:00",
                    "ends_at": "2030-08-14T11:00:00"
                }
            ]'::jsonb,
            '{"additional_occurrences": 1, "pattern": "weekly"}'::jsonb
        )
        $$,
        :'userID', :'groupID', :'eventCategoryID', :'eventCategoryID'
    ),
    'OCG01',
    'recurring events require starts_at',
    'Should reject missing start date on the anchor event'
);

-- Should reject generated events whose meeting exceeds the provider maximum duration
select throws_ok(
    format(
        $$
        select add_event_series(
            %L::uuid,
            %L::uuid,
            '[
                {
                    "name": "Long Meeting Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "capacity": 50,
                    "meeting_provider_id": "zoom",
                    "meeting_requested": true,
                    "starts_at": "2030-10-05T09:00:00",
                    "ends_at": "2030-10-05T22:00:00"
                },
                {
                    "name": "Long Meeting Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "capacity": 50,
                    "meeting_provider_id": "zoom",
                    "meeting_requested": true,
                    "starts_at": "2030-10-12T09:00:00",
                    "ends_at": "2030-10-12T22:00:00"
                }
            ]'::jsonb,
            '{"additional_occurrences": 1, "pattern": "weekly"}'::jsonb,
            '{"zoom": {"max_duration_minutes": 720, "max_participants": 500, "min_duration_minutes": 5}}'::jsonb
        )
        $$,
        :'userID', :'groupID', :'eventCategoryID', :'eventCategoryID'
    ),
    'OCG01',
    'event meeting duration (780 minutes) must be between 5 and 720 minutes',
    'Should reject generated events whose meeting exceeds the provider maximum duration'
);

-- Should roll back the whole series when one generated event fails
select throws_ok(
    format(
        $$
        select add_event_series(
            %L::uuid,
            %L::uuid,
            '[
                {
                    "name": "Rollback Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2030-09-07T10:00:00",
                    "ends_at": "2030-09-07T11:00:00"
                },
                {
                    "name": "Rollback Weekly Study Group",
                    "description": "Base event",
                    "timezone": "UTC",
                    "category_id": "%s",
                    "kind_id": "virtual",
                    "starts_at": "2020-09-14T10:00:00",
                    "ends_at": "2020-09-14T11:00:00"
                }
            ]'::jsonb,
            '{"additional_occurrences": 1, "pattern": "weekly"}'::jsonb
        )
        $$,
        :'userID', :'groupID', :'eventCategoryID', :'eventCategoryID'
    ),
    'OCG01',
    'event starts_at cannot be in the past',
    'Should roll back the whole series when one generated event fails'
);

-- Should leave no partial rows after a generated event fails
select results_eq(
    $$
        select
            (select count(*)::int from event where name = 'Rollback Weekly Study Group'),
            (select count(*)::int from event_series)
    $$,
    $$
        values (0, 2)
    $$,
    'Should leave no partial rows after a generated event fails'
);

-- Should snapshot the accepted team on every occurrence when organizers are omitted
select lives_ok(
    format(
        $$select add_event_series(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)$$,
        :'userID',
        :'groupID',
        jsonb_build_array(
            jsonb_build_object(
                'category_id', :'eventCategoryID',
                'description', 'Base event',
                'ends_at', '2030-10-07T11:00:00',
                'kind_id', 'virtual',
                'name', 'Team Organizers Study Group',
                'starts_at', '2030-10-07T10:00:00',
                'timezone', 'UTC'
            ),
            jsonb_build_object(
                'category_id', :'eventCategoryID',
                'description', 'Base event',
                'ends_at', '2030-10-14T11:00:00',
                'kind_id', 'virtual',
                'name', 'Team Organizers Study Group',
                'starts_at', '2030-10-14T10:00:00',
                'timezone', 'UTC'
            )
        ),
        '{"additional_occurrences": 1, "pattern": "weekly"}'::jsonb
    ),
    'Should snapshot the accepted team on every occurrence when organizers are omitted'
);
select results_eq(
    $$
        select e.starts_at, eo.user_id, eo."order"
        from event e
        join event_organizer eo using (event_id)
        where e.name = 'Team Organizers Study Group'
        order by e.starts_at, eo."order"
    $$,
    format(
        $$
            values
                ('2030-10-07 10:00:00+00'::timestamptz, %L::uuid, 1),
                ('2030-10-07 10:00:00+00'::timestamptz, %L::uuid, 2),
                ('2030-10-14 10:00:00+00'::timestamptz, %L::uuid, 1),
                ('2030-10-14 10:00:00+00'::timestamptz, %L::uuid, 2)
        $$,
        :'teamMemberID',
        :'secondTeamMemberID',
        :'teamMemberID',
        :'secondTeamMemberID'
    ),
    'Should store the accepted team as organizers of every occurrence'
);

-- Should store submitted organizers on every occurrence
select lives_ok(
    format(
        $$select add_event_series(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)$$,
        :'userID',
        :'groupID',
        jsonb_build_array(
            jsonb_build_object(
                'category_id', :'eventCategoryID',
                'description', 'Base event',
                'ends_at', '2030-11-07T11:00:00',
                'kind_id', 'virtual',
                'name', 'Submitted Organizers Study Group',
                'organizers', jsonb_build_array(:'secondTeamMemberID', :'teamMemberID'),
                'starts_at', '2030-11-07T10:00:00',
                'timezone', 'UTC'
            ),
            jsonb_build_object(
                'category_id', :'eventCategoryID',
                'description', 'Base event',
                'ends_at', '2030-11-14T11:00:00',
                'kind_id', 'virtual',
                'name', 'Submitted Organizers Study Group',
                'organizers', jsonb_build_array(:'secondTeamMemberID', :'teamMemberID'),
                'starts_at', '2030-11-14T10:00:00',
                'timezone', 'UTC'
            )
        ),
        '{"additional_occurrences": 1, "pattern": "weekly"}'::jsonb
    ),
    'Should store submitted organizers on every occurrence'
);
select results_eq(
    $$
        select e.starts_at, eo.user_id, eo."order"
        from event e
        join event_organizer eo using (event_id)
        where e.name = 'Submitted Organizers Study Group'
        order by e.starts_at, eo."order"
    $$,
    format(
        $$
            values
                ('2030-11-07 10:00:00+00'::timestamptz, %L::uuid, 1),
                ('2030-11-07 10:00:00+00'::timestamptz, %L::uuid, 2),
                ('2030-11-14 10:00:00+00'::timestamptz, %L::uuid, 1),
                ('2030-11-14 10:00:00+00'::timestamptz, %L::uuid, 2)
        $$,
        :'secondTeamMemberID',
        :'teamMemberID',
        :'secondTeamMemberID',
        :'teamMemberID'
    ),
    'Should store submitted organizers in order on every occurrence'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
