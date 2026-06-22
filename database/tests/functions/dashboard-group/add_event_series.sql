-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a030000-0000-0000-0000-000000000001'
\set eventCategoryID '3a030000-0000-0000-0000-000000000002'
\set groupCategoryID '3a030000-0000-0000-0000-000000000003'
\set groupID '3a030000-0000-0000-0000-000000000004'
\set userID '3a030000-0000-0000-0000-000000000005'

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
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- User
insert into "user" (user_id, email, username, auth_hash, name)
values (:'userID', 'organizer@example.com', 'organizer', 'hash', 'Organizer');

-- Event Category
insert into event_category (event_category_id, name, alliance_id)
values (:'eventCategoryID', 'Meetup', :'allianceID');

-- Group Category
insert into group_category (group_category_id, name, alliance_id)
values (:'groupCategoryID', 'Technology', :'allianceID');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'allianceID',
    'Test Group',
    'test-group',
    'A test group',
    :'groupCategoryID'
);

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
    $$,
    $$
        values (1, 'weekly'::text, 'UTC'::text)
    $$,
    'Should store recurrence metadata for the series'
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
    'P0001',
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
    'P0001',
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
    'P0001',
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
    'P0001',
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
    'P0001',
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
    'P0001',
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
    'P0001',
    'recurring events require starts_at',
    'Should reject missing start date on the anchor event'
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
    'P0001',
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
        values (0, 1)
    $$,
    'Should leave no partial rows after a generated event fails'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
