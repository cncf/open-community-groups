-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '5e0b0000-0000-0000-0000-000000000001'
\set eventCappedID '5e0b0000-0000-0000-0000-000000000002'
\set eventCategoryID '5e0b0000-0000-0000-0000-000000000003'
\set eventFullID '5e0b0000-0000-0000-0000-000000000004'
\set eventLimitedID '5e0b0000-0000-0000-0000-000000000005'
\set eventQuestionsID '5e0b0000-0000-0000-0000-000000000006'
\set eventRegistrationClosedID '5e0b0000-0000-0000-0000-000000000015'
\set eventRegistrationOpenUntilStartID '5e0b0000-0000-0000-0000-000000000016'
\set eventUnlimitedID '5e0b0000-0000-0000-0000-000000000007'
\set groupCategoryID '5e0b0000-0000-0000-0000-000000000008'
\set groupID '5e0b0000-0000-0000-0000-000000000009'
\set questionID '5e0b0000-0000-0000-0000-00000000000a'
\set questionsWaitlistUserID '5e0b0000-0000-0000-0000-00000000000b'
\set unknownEventID '5e0b0000-0000-0000-0000-00000000000c'
\set user1ID '5e0b0000-0000-0000-0000-00000000000d'
\set user2ID '5e0b0000-0000-0000-0000-00000000000e'
\set user3ID '5e0b0000-0000-0000-0000-00000000000f'
\set user4ID '5e0b0000-0000-0000-0000-000000000010'
\set user5ID '5e0b0000-0000-0000-0000-000000000011'
\set user6ID '5e0b0000-0000-0000-0000-000000000012'
\set user7ID '5e0b0000-0000-0000-0000-000000000013'
\set user8ID '5e0b0000-0000-0000-0000-000000000014'
\set user9ID '5e0b0000-0000-0000-0000-000000000017'

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

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Active Group', 'active-group');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'user1ID', 'h1', 'u1@test.com', true, 'u1'),
    (:'user2ID', 'h2', 'u2@test.com', true, 'u2'),
    (:'user3ID', 'h3', 'u3@test.com', true, 'u3'),
    (:'user4ID', 'h4', 'u4@test.com', true, 'u4'),
    (:'user5ID', 'h5', 'u5@test.com', true, 'u5'),
    (:'user6ID', 'h6', 'u6@test.com', true, 'u6'),
    (:'user7ID', 'h7', 'u7@test.com', true, 'u7'),
    (:'user8ID', 'h8', 'u8@test.com', true, 'u8'),
    (:'user9ID', 'h10', 'u9@test.com', true, 'u9'),
    (:'questionsWaitlistUserID', 'h9', 'rq-waitlist@test.com', true, 'rq-waitlist');

-- Events
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    canceled,
    deleted,
    capacity,
    ends_at,
    registration_ends_at,
    registration_starts_at,
    starts_at,
    waitlist_enabled
)
values
    (
        :'eventCappedID',
        'Capped',
        'capped',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        false,
        false,
        5,
        null,
        null,
        null,
        null,
        true
    ),
    (
        :'eventFullID',
        'Full',
        'full',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        false,
        false,
        1,
        null,
        null,
        null,
        null,
        true
    ),
    (
        :'eventLimitedID',
        'Limited',
        'limited',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        false,
        false,
        3,
        null,
        null,
        null,
        null,
        true
    ),
    (
        :'eventUnlimitedID',
        'Unlimited',
        'unlimited',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        false,
        false,
        null,
        null,
        null,
        null,
        null,
        false
    ),
    (
        :'eventRegistrationClosedID',
        'Closed Registration',
        'closed-registration',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        false,
        false,
        2,
        null,
        current_timestamp - interval '1 hour',
        null,
        null,
        true
    ),
    (
        :'eventRegistrationOpenUntilStartID',
        'Registration Open Until Start',
        'registration-open-until-start',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        false,
        false,
        2,
        current_timestamp + interval '1 hour',
        null,
        current_timestamp - interval '2 hours',
        current_timestamp - interval '1 hour',
        true
    );

-- Event requiring registration answers before promoted waitlist users are confirmed
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    capacity,
    waitlist_enabled,
    registration_questions
)
values (
    :'eventQuestionsID',
    'Waitlist Questions Event',
    'waitlist-questions-event',
    'd',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true,
    1,
    true,
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb
);

-- Existing attendees
insert into event_attendee (event_id, user_id)
values
    (:'eventFullID', :'user1ID'),
    (:'eventLimitedID', :'user1ID');

-- Waitlist entries
insert into event_waitlist (event_id, user_id, created_at)
values
    (:'eventCappedID', :'user5ID', '2024-01-01 00:00:00+00'),
    (:'eventCappedID', :'user6ID', '2024-01-02 00:00:00+00'),
    (:'eventCappedID', :'user7ID', '2024-01-03 00:00:00+00'),
    (:'eventFullID', :'user2ID', '2024-01-01 00:00:00+00'),
    (:'eventLimitedID', :'user2ID', '2024-01-01 00:00:00+00'),
    (:'eventLimitedID', :'user3ID', '2024-01-02 00:00:00+00'),
    (:'eventLimitedID', :'user4ID', '2024-01-03 00:00:00+00'),
    (:'eventRegistrationClosedID', :'user8ID', '2024-01-01 00:00:00+00'),
    (:'eventRegistrationOpenUntilStartID', :'user9ID', '2024-01-01 00:00:00+00'),
    (:'eventUnlimitedID', :'user7ID', '2024-01-01 00:00:00+00'),
    (:'eventUnlimitedID', :'user8ID', '2024-01-02 00:00:00+00'),
    (:'eventQuestionsID', :'questionsWaitlistUserID', '2024-01-01 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore non-positive slot requests
select is(
    promote_event_waitlist(:'eventLimitedID'::uuid, 0),
    array[]::uuid[],
    'Returns an empty list when the requested slots are not positive'
);

-- Should leave state unchanged when the requested slots are not positive
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'eventLimitedID'::uuid
            ),
            'waitlist', (
                select jsonb_agg(user_id order by created_at asc, user_id asc)
                from event_waitlist
                where event_id = :'eventLimitedID'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s"],"waitlist":["%s","%s","%s"]}',
        :'user1ID',
        :'user2ID',
        :'user3ID',
        :'user4ID'
    )::jsonb,
    'Keeps attendees and waitlist unchanged when the requested slots are not positive'
);

-- Should return an empty list for an unknown event
select is(
    promote_event_waitlist(:'unknownEventID'::uuid),
    array[]::uuid[],
    'Returns an empty list for an unknown event'
);

-- Should return no promoted users when the registration window is closed
select is(
    promote_event_waitlist(:'eventRegistrationClosedID'::uuid),
    array[]::uuid[],
    'Returns an empty list when the registration window is closed'
);

-- Should keep queued users when the registration window is closed
select is(
    (
        select jsonb_agg(user_id order by created_at asc, user_id asc)
        from event_waitlist
        where event_id = :'eventRegistrationClosedID'::uuid
    ),
    format('["%s"]', :'user8ID')::jsonb,
    'Keeps waitlist entries queued when the registration window is closed'
);

-- Should return no promoted users when open-only registration reached event start
select is(
    promote_event_waitlist(:'eventRegistrationOpenUntilStartID'::uuid),
    array[]::uuid[],
    'Returns an empty list when an open-only registration window reaches the event start'
);

-- Should keep queued users when open-only registration reached event start
select is(
    (
        select jsonb_agg(user_id order by created_at asc, user_id asc)
        from event_waitlist
        where event_id = :'eventRegistrationOpenUntilStartID'::uuid
    ),
    format('["%s"]', :'user9ID')::jsonb,
    'Keeps waitlist entries queued when an open-only registration window reaches the event start'
);

-- Should return an empty list when no seats are available
select is(
    promote_event_waitlist(:'eventFullID'::uuid),
    array[]::uuid[],
    'Returns an empty list when the event has no available seats'
);

-- Should promote the oldest waitlist entries up to the available capacity
select is(
    promote_event_waitlist(:'eventLimitedID'::uuid),
    array[:'user2ID'::uuid, :'user3ID'::uuid],
    'Promotes the oldest waitlist entries first when seats are available'
);

-- Should move promoted users into attendees and keep remaining waitlist order
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'eventLimitedID'::uuid
            ),
            'waitlist', (
                select jsonb_agg(user_id order by created_at asc, user_id asc)
                from event_waitlist
                where event_id = :'eventLimitedID'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s","%s","%s"],"waitlist":["%s"]}',
        :'user1ID',
        :'user2ID',
        :'user3ID',
        :'user4ID'
    )::jsonb,
    'Moves promoted users into attendees and leaves the remaining waitlist intact'
);

select is(
    (
        select jsonb_object_agg(user_id, manually_invited order by user_id)
        from event_attendee
        where event_id = :'eventLimitedID'::uuid
    ),
    format(
        '{"%s":false,"%s":false,"%s":false}',
        :'user1ID',
        :'user2ID',
        :'user3ID'
    )::jsonb,
    'Should keep promoted waitlist attendees not manually invited'
);

-- Should respect an explicit slots cap even when more seats are available
select is(
    promote_event_waitlist(:'eventCappedID'::uuid, 1),
    array[:'user5ID'::uuid],
    'Promotes only the requested number of waitlist entries when slots are capped'
);

-- Should promote all waitlist users for an unlimited-capacity event
select is(
    promote_event_waitlist(:'eventUnlimitedID'::uuid),
    array[:'user7ID'::uuid, :'user8ID'::uuid],
    'Promotes the full waitlist when the event has unlimited capacity'
);

-- Should clear the unlimited-capacity waitlist after promotion
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'eventUnlimitedID'::uuid
            ),
            'waitlist', (
                select coalesce(jsonb_agg(user_id order by created_at asc, user_id asc), '[]'::jsonb)
                from event_waitlist
                where event_id = :'eventUnlimitedID'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s","%s"],"waitlist":[]}',
        :'user7ID',
        :'user8ID'
    )::jsonb,
    'Clears the waitlist after promoting all users for an unlimited-capacity event'
);

-- Should keep working when trigger-based exclusivity is enabled
select is(
    promote_event_waitlist(:'eventCappedID'::uuid),
    array[:'user6ID'::uuid, :'user7ID'::uuid],
    'Promotes waitlist users successfully with attendee and waitlist exclusivity triggers enabled'
);

-- Should promote waitlisted users into pending registration when questions are required
select is(
    promote_event_waitlist(:'eventQuestionsID'::uuid),
    array[:'questionsWaitlistUserID'::uuid],
    'Should promote waitlisted users into pending registration when questions are required'
);

-- Should store pending registration status for promoted waitlist users
select is(
    (
        select status
        from event_attendee
        where event_id = :'eventQuestionsID'::uuid
        and user_id = :'questionsWaitlistUserID'::uuid
    ),
    'registration-questions-pending',
    'Should store pending registration status for promoted waitlist users'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
