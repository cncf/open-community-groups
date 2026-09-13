-- E2E seed: events.
-- Depends on: 20_groups.sql (groups and group catalog links).

-- ============================================================================
-- EVENTS
-- ============================================================================

-- Primary group events
-- Upcoming in-person event with full location data
insert into event (
    event_id, name, slug, description, description_short, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    venue_name, venue_address, venue_city, venue_state_code, venue_state_name, venue_country_name,
    venue_country_code, venue_zip_code, location, banner_url, logo_url, capacity,
    tags, meetup_url, meeting_join_url, photos_urls
) values (
    '55555555-5555-5555-5555-555555555501',
    'Upcoming In-Person Event',
    'alpha-event-1',
    'Upcoming in-person event used for attendance and dashboard coverage.',
    'Join the primary meetup for end-to-end coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'in-person',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '10 days',
    now() + interval '10 days 2 hours',
    'Tech Conference Center',
    '123 Main Street',
    'New York',
    'NY',
    'NY',
    'United States',
    'US',
    '10001',
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    '/static/images/e2e/event-banner.svg',
    '/static/images/e2e/event-logo.svg',
    100,
    '{"meetup", "tech", "networking"}',
    'https://www.meetup.com/test-group/events/123456789/',
    'https://zoom.us/j/1234567890',
    -- The first photo path intentionally does not exist: e2e tests rely on it
    -- to cover broken gallery image fallback behavior. Do not "fix" it.
    '{"/static/images/e2e/missing-event-gallery-photo.svg", "/static/images/e2e/event-photo-2.svg"}'
);


-- Upcoming virtual event with recording
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city,
    meeting_recording_url
) values (
    '55555555-5555-5555-5555-555555555502',
    'Upcoming Virtual Event',
    'alpha-event-2',
    'Upcoming virtual event used for attendee empty-state coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '20 days',
    now() + interval '20 days 2 hours',
    'San Francisco',
    'https://www.youtube.com/watch?v=test123'
);

-- Upcoming hybrid event
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city
) values (
    '55555555-5555-5555-5555-555555555503',
    'Upcoming Hybrid Event',
    'alpha-event-3',
    'Upcoming hybrid event used for public group-page coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '30 days',
    now() + interval '30 days 2 hours',
    null
);

-- Secondary group events
-- Canceled in-person event for unpublished-state coverage
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city, canceled
) values (
    '55555555-5555-5555-5555-555555555504',
    'Canceled In-Person Event',
    'beta-event-1',
    'Canceled in-person event used for filtering coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'in-person',
    '44444444-4444-4444-4444-444444444442',
    false,
    now() + interval '11 days',
    now() + interval '11 days 2 hours',
    'Los Angeles',
    true
);

-- Upcoming virtual and hybrid events
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city
) values (
    '55555555-5555-5555-5555-555555555505',
    'Secondary Virtual Event',
    'beta-event-2',
    'Secondary virtual event for user dashboard filtering coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444442',
    true,
    now() + interval '21 days',
    now() + interval '21 days 2 hours',
    'Los Angeles'
), (
    '55555555-5555-5555-5555-555555555506',
    'Secondary Hybrid Event',
    'beta-event-3',
    'Secondary hybrid event for explore coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444442',
    true,
    now() + interval '31 days',
    now() + interval '31 days 2 hours',
    null
);

-- Search-focused group events
-- In-person, virtual, and hybrid events for search coverage
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at, venue_city
) values (
    '55555555-5555-5555-5555-555555555507',
    'Observability In-Person Event',
    'gamma-event-1',
    'In-person event for the observability-focused group.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'in-person',
    '44444444-4444-4444-4444-444444444443',
    true,
    now() + interval '12 days',
    now() + interval '12 days 2 hours',
    'Chicago'
), (
    '55555555-5555-5555-5555-555555555508',
    'Observability Virtual Event',
    'gamma-event-2',
    'Virtual event for the observability-focused group.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444443',
    true,
    now() + interval '22 days',
    now() + interval '22 days 2 hours',
    'Chicago'
), (
    '55555555-5555-5555-5555-555555555509',
    'Observability Hybrid Event',
    'gamma-event-3',
    'Hybrid event for the observability-focused group.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444443',
    true,
    now() + interval '32 days',
    now() + interval '32 days 2 hours',
    null
);

-- Delta group events
-- Past, virtual, and hybrid events
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at
) values (
    '55555555-5555-5555-5555-555555555510',
    'Delta Event One',
    'delta-event-1',
    'In-person event for Delta group (past).',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'in-person',
    '44444444-4444-4444-4444-444444444444',
    true,
    now() - interval '13 days',
    now() - interval '13 days' + interval '2 hours'
), (
    '55555555-5555-5555-5555-555555555511',
    'Delta Event Two',
    'delta-event-2',
    'Virtual event for Delta group.',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'virtual',
    '44444444-4444-4444-4444-444444444444',
    true,
    now() + interval '23 days',
    now() + interval '23 days 2 hours'
), (
    '55555555-5555-5555-5555-555555555512',
    'Delta Event Three',
    'delta-event-3',
    'Hybrid event for Delta group.',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'hybrid',
    '44444444-4444-4444-4444-444444444444',
    true,
    now() + interval '33 days',
    now() + interval '33 days 2 hours'
);

-- Epsilon group events
-- Past, virtual, and hybrid events
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at
) values (
    '55555555-5555-5555-5555-555555555513',
    'Epsilon Event One',
    'epsilon-event-1',
    'In-person event for Epsilon group (past).',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'in-person',
    '44444444-4444-4444-4444-444444444445',
    true,
    now() - interval '14 days',
    now() - interval '14 days' + interval '2 hours'
), (
    '55555555-5555-5555-5555-555555555514',
    'Epsilon Event Two',
    'epsilon-event-2',
    'Virtual event for Epsilon group.',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'virtual',
    '44444444-4444-4444-4444-444444444445',
    true,
    now() + interval '24 days',
    now() + interval '24 days 2 hours'
), (
    '55555555-5555-5555-5555-555555555515',
    'Epsilon Event Three',
    'epsilon-event-3',
    'Hybrid event for Epsilon group.',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'hybrid',
    '44444444-4444-4444-4444-444444444445',
    true,
    now() + interval '34 days',
    now() + interval '34 days 2 hours'
);

-- Zeta group events
-- Past, virtual, and hybrid events
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at
) values (
    '55555555-5555-5555-5555-555555555516',
    'Zeta Event One',
    'zeta-event-1',
    'In-person event for Zeta group (past).',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'in-person',
    '44444444-4444-4444-4444-444444444446',
    true,
    now() - interval '15 days',
    now() - interval '15 days' + interval '2 hours'
), (
    '55555555-5555-5555-5555-555555555517',
    'Zeta Event Two',
    'zeta-event-2',
    'Virtual event for Zeta group.',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'virtual',
    '44444444-4444-4444-4444-444444444446',
    true,
    now() + interval '25 days',
    now() + interval '25 days 2 hours'
), (
    '55555555-5555-5555-5555-555555555518',
    'Zeta Event Three',
    'zeta-event-3',
    'Hybrid event for Zeta group.',
    'UTC',
    '33333333-3333-3333-3333-333333333332',
    'hybrid',
    '44444444-4444-4444-4444-444444444446',
    true,
    now() + interval '35 days',
    now() + interval '35 days 2 hours'
);

-- Primary group events for CFS, filtering, and waitlist coverage
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    cfs_enabled, cfs_description, cfs_starts_at, cfs_ends_at,
    meeting_recording_url
) values (
    '55555555-5555-5555-5555-555555555519',
    'Event With Active CFS',
    'alpha-cfs-summit',
    'Future event with an active call for speakers.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    -- Fixed clock hours so specs can add sessions at hard-coded times of day.
    date_trunc('day', now()) + interval '45 days 10 hours',
    date_trunc('day', now()) + interval '45 days 14 hours',
    true,
    'Submit your best talks for our extended speaker program.',
    now() - interval '2 days',
    now() + interval '30 days',
    null
), (
    '55555555-5555-5555-5555-555555555520',
    'Past Event For Filtering',
    'alpha-past-roundup',
    'Past event used for dashboard and user filtering coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() - interval '5 days',
    now() - interval '5 days' + interval '2 hours',
    null,
    null,
    null,
    null,
    'https://recordings.example.test/alpha-past-roundup'
);

-- Publish the past event recording so the public page shows the recording link.
update event
set meeting_recording_published = true
where event_id = '55555555-5555-5555-5555-555555555520';

-- Second past event so the dashboard past events tab can paginate.
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at
) values (
    '55555555-5555-5555-5555-555555555536',
    'Past Pagination Event',
    'alpha-past-pagination',
    'Older past event used for past events pagination coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() - interval '20 days',
    now() - interval '20 days' + interval '2 hours'
);

-- Events reserved for call-for-speakers window coverage.
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    cfs_enabled, cfs_description, cfs_starts_at, cfs_ends_at
) values (
    '55555555-5555-5555-5555-555555555533',
    'Upcoming Call for Speakers Window',
    'alpha-cfs-upcoming',
    'Future event whose call for speakers has not opened yet.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '400 days',
    now() + interval '400 days 2 hours',
    true,
    'Speaker submissions will open later for this event.',
    now() + interval '300 days',
    now() + interval '330 days'
), (
    '55555555-5555-5555-5555-555555555534',
    'Closed Call for Speakers Window',
    'alpha-cfs-closed',
    'Future event whose call for speakers has already closed.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '400 days',
    now() + interval '400 days 2 hours',
    true,
    'Speaker submissions are closed for this event.',
    now() - interval '30 days',
    now() - interval '5 days'
);

insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    capacity, waitlist_enabled
) values (
    '55555555-5555-5555-5555-555555555521',
    'Full Event With Waitlist',
    'alpha-waitlist-lab',
    'Future event dedicated to waitlist and attendee coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '60 days',
    now() + interval '60 days 2 hours',
    1,
    true
), (
    '55555555-5555-5555-5555-555555555526',
    'Dashboard Waitlist Table Lab',
    'alpha-dashboard-waitlist-lab',
    'Future event dedicated to dashboard waitlist table coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '59 days',
    now() + interval '59 days 2 hours',
    1,
    true
);

-- Events reserved for cancellation lifecycle and canceled invitation history coverage.
insert into event (
    event_id,
    canceled,
    description,
    ends_at,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    registration_questions,
    slug,
    starts_at,
    timezone
)
values (
    '55555555-5555-5555-5555-555555555527',
    false,
    'Future event used to verify attendee state transitions after event cancellation.',
    now() + interval '62 days 2 hours',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'Event Cancellation Lifecycle',
    true,
    '[{"id":"57555555-5555-5555-5555-555555555527","kind":"free-text","prompt":"What should the organizers know?","required":true,"options":[]}]'::jsonb,
    'alpha-event-cancellation-lifecycle',
    now() + interval '62 days',
    'UTC'
), (
    '55555555-5555-5555-5555-555555555528',
    true,
    'Canceled event used to preserve canceled invitation history in the dashboard.',
    now() + interval '63 days 2 hours',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'Canceled Invitation History',
    true,
    '[]'::jsonb,
    'alpha-canceled-invitation-history',
    now() + interval '63 days',
    'UTC'
);

-- Published test event for direct event-page badge coverage.
insert into event (
    event_id, name, slug, description, description_short, timezone, event_category_id,
    event_kind_id, group_id, published, test_event, starts_at, ends_at
) values (
    '55555555-5555-5555-5555-555555555524',
    'Test Event Page Badge',
    'alpha-test-event-badge',
    'Published test event used for event page badge coverage.',
    'Direct link coverage for test event badges.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    now() + interval '70 days',
    now() + interval '70 days 2 hours'
);

-- Registration questions event with answered attendees.
insert into event (
    event_id, name, slug, description, description_short, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    capacity, registration_questions
) values (
    '55555555-5555-5555-5555-555555555525',
    'Registration Answers Lab',
    'alpha-registration-answers-lab',
    'Future event with realistic registration questions and submitted attendee answers.',
    'Review realistic attendee questionnaire answers in the dashboard.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444441',
    true,
    now() + interval '80 days',
    now() + interval '80 days 2 hours',
    60,
    '[
        {
            "id": "57555555-5555-5555-5555-555555555501",
            "kind": "free-text",
            "prompt": "What are you hoping to learn from this event?",
            "required": true,
            "options": []
        },
        {
            "id": "57555555-5555-5555-5555-555555555502",
            "kind": "single-select",
            "prompt": "Preferred session format",
            "required": true,
            "options": [
                { "id": "58555555-5555-5555-5555-555555555501", "label": "Hands-on workshop" },
                { "id": "58555555-5555-5555-5555-555555555502", "label": "Panel discussion" },
                { "id": "58555555-5555-5555-5555-555555555503", "label": "Lightning talks" }
            ]
        },
        {
            "id": "57555555-5555-5555-5555-555555555503",
            "kind": "multi-select",
            "prompt": "Topics you want covered",
            "required": true,
            "options": [
                { "id": "58555555-5555-5555-5555-555555555504", "label": "Platform reliability" },
                { "id": "58555555-5555-5555-5555-555555555505", "label": "Developer experience" },
                { "id": "58555555-5555-5555-5555-555555555506", "label": "Security and compliance" },
                { "id": "58555555-5555-5555-5555-555555555507", "label": "Open source governance" }
            ]
        },
        {
            "id": "57555555-5555-5555-5555-555555555504",
            "kind": "free-text",
            "prompt": "Anything the organizers should know?",
            "required": false,
            "options": []
        }
    ]'::jsonb
);

-- Public attendance workflow fixtures for Playwright coverage.
insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, published, test_event, starts_at, ends_at,
    attendee_approval_required, registration_starts_at, registration_ends_at
) values (
    '55555555-5555-5555-5555-555555555529',
    'Open Public Check-In',
    'alpha-open-public-check-in',
    'Live event used to verify attendee credentials and organizer scanning.',
    'Live event with organizer check-in available.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    now() - interval '1 hour',
    now() + interval '2 days',
    false,
    null,
    null
), (
    '55555555-5555-5555-5555-555555555530',
    'Approval Required Attendance',
    'alpha-approval-required-attendance',
    'Future event used to verify public invitation request states.',
    'Future event requiring organizer approval.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    now() + interval '120 days',
    now() + interval '120 days 2 hours',
    true,
    now() - interval '1 day',
    now() + interval '100 days'
);

-- Meeting access details for the live event used in join link coverage.
update event
set meeting_join_url = 'https://meet.example.com/e2e-open-check-in',
    meeting_join_instructions = 'Use the passcode shared with attendees to join the room.'
where event_id = '55555555-5555-5555-5555-555555555529';

-- Public event state fixtures for canceled and unpublished page coverage.
insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, published, test_event, canceled,
    starts_at, ends_at, cfs_enabled, cfs_description, cfs_starts_at, cfs_ends_at,
    meeting_join_url, meeting_join_instructions
) values (
    '55555555-5555-5555-5555-555555555531',
    'Canceled Public Event',
    'alpha-canceled-public-event',
    'Canceled event used to verify unavailable public actions.',
    'Canceled event with public actions disabled.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    true,
    now() + interval '30 days',
    now() + interval '30 days 2 hours',
    true,
    'Speaker submissions would be open if the event were active.',
    now() - interval '1 day',
    now() + interval '10 days',
    'https://meet.example.com/e2e-canceled-event',
    'Join the canceled event using the private meeting room.'
), (
    '55555555-5555-5555-5555-555555555532',
    'Unpublished Public Event',
    'alpha-unpublished-public-event',
    'Unpublished event used to verify public route protection.',
    'Unpublished event hidden from the public site.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    false,
    true,
    false,
    now() + interval '31 days',
    now() + interval '31 days 2 hours',
    false,
    null,
    null,
    null,
    null,
    null
);

-- Multi-day public event used for agenda day tab coverage.
insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, published, test_event, canceled,
    starts_at, ends_at, cfs_enabled, cfs_description, cfs_starts_at, cfs_ends_at,
    meeting_join_url, meeting_join_instructions
) values (
    '55555555-5555-5555-5555-555555555535',
    'Multi Day Summit',
    'alpha-multi-day-summit',
    'Two-day summit used to verify the public multi-day agenda tabs.',
    'Two-day summit with a per-day agenda.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    false,
    now() + interval '40 days',
    now() + interval '41 days 2 hours',
    false,
    null,
    null,
    null,
    null,
    null
);

-- Ticketed payment fixtures reserved for the Playwright suite.
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, payment_currency_code, published, starts_at, ends_at,
    waitlist_enabled
) values (
    '55555555-5555-5555-5555-555555555522',
    'Paid Tier Draft Event',
    'alpha-payments-draft',
    'Paid-tier event used for payment editor and validation coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    now() + interval '90 days',
    now() + interval '90 days 3 hours',
    false
), (
    '55555555-5555-5555-5555-555555555523',
    'Paid Tier Refund Review Event',
    'alpha-payments-refunds',
    'Paid-tier event used for organizer refund review coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    now() + interval '95 days',
    now() + interval '95 days 2 hours',
    false
);

-- Manual-tax fixture whose saved provider rate is no longer available.
insert into event (
    event_id, name, slug, description, timezone, event_category_id,
    event_kind_id, group_id, payment_currency_code, published, starts_at, ends_at,
    waitlist_enabled, tax_behavior, tax_calculation_mode, manual_tax_rate_ids
) values (
    '55555555-5555-5555-5555-555555555921',
    'Unavailable Manual Tax Rate Lab',
    'alpha-manual-tax-unavailable',
    'Manual-tax event used to verify unavailable saved provider rates.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    false,
    now() + interval '92 days',
    now() + interval '92 days 2 hours',
    false,
    'inclusive',
    'manual',
    array['txr_e2e_unavailable']::text[]
);

-- Registration window fixtures for Playwright coverage.
insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, payment_currency_code, published,
    test_event, starts_at, ends_at, capacity,
    waitlist_enabled, attendee_approval_required, registration_starts_at,
    registration_ends_at, registration_questions
) values (
    '55555555-5555-5555-5555-555555555901',
    'Registration Window Paid Closed',
    'alpha-registration-window-paid-closed',
    'Paid event with a closed registration window.',
    'Paid event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '100 days',
    now() + interval '100 days 2 hours',
    null,
    false,
    false,
    now() - interval '10 days',
    now() - interval '1 day',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555902',
    'Registration Window Paid Future',
    'alpha-registration-window-paid-future',
    'Paid event with registration opening later.',
    'Paid event with future registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '101 days',
    now() + interval '101 days 2 hours',
    null,
    false,
    false,
    now() + interval '1 day',
    now() + interval '30 days',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555903',
    'Registration Window Paid Open',
    'alpha-registration-window-paid-open',
    'Paid event with registration currently open.',
    'Paid event with open registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '102 days',
    now() + interval '102 days 2 hours',
    null,
    false,
    false,
    now() - interval '1 day',
    now() + interval '30 days',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555904',
    'Registration Window Free Closed',
    'alpha-registration-window-free-closed',
    'Free event with a closed registration window.',
    'Free event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '103 days',
    now() + interval '103 days 2 hours',
    null,
    false,
    false,
    null,
    now() - interval '1 day',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555905',
    'Registration Window Approval Closed',
    'alpha-registration-window-approval-closed',
    'Approval-required event with a closed registration window.',
    'Approval-required event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '104 days',
    now() + interval '104 days 2 hours',
    null,
    false,
    true,
    null,
    now() - interval '1 day',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555906',
    'Registration Window Waitlist Closed',
    'alpha-registration-window-waitlist-closed',
    'Full waitlist event with a closed registration window.',
    'Waitlist event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '105 days',
    now() + interval '105 days 2 hours',
    1,
    true,
    false,
    null,
    now() - interval '1 day',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555907',
    'Registration Window Close Only Open',
    'alpha-registration-window-close-only-open',
    'Free event with only a future registration close date.',
    'Free event with close-only registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '106 days',
    now() + interval '106 days 2 hours',
    null,
    false,
    false,
    null,
    now() + interval '30 days',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555908',
    'Registration Window Open Only Closed',
    'alpha-registration-window-open-only-closed',
    'Live event where open-only registration closed at event start.',
    'Free event with open-only registration closed at event start.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() - interval '1 day',
    now() + interval '30 days',
    null,
    false,
    false,
    now() - interval '10 days',
    null,
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555909',
    'Registration Window Questions Closed',
    'alpha-registration-window-questions-closed',
    'Registration questions event with a closed registration window.',
    'Questions event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '107 days',
    now() + interval '107 days 2 hours',
    null,
    false,
    false,
    null,
    now() - interval '1 day',
    '[{"id":"57555555-5555-5555-5555-555555555909","kind":"free-text","prompt":"What should the organizers know?","required":true,"options":[]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555910',
    'Registration Window Manual Invite Closed',
    'alpha-registration-window-manual-invite-closed',
    'Registration questions event with a manual invite after closing.',
    'Manual invite event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '108 days',
    now() + interval '108 days 2 hours',
    null,
    false,
    false,
    null,
    now() - interval '1 day',
    '[{"id":"57555555-5555-5555-5555-555555555910","kind":"free-text","prompt":"What should the organizers know?","required":true,"options":[]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555911',
    'Registration Window Pending Payment Closed',
    'alpha-registration-window-pending-payment-closed',
    'Paid questions event with an active pending checkout after closing.',
    'Pending payment event with closed registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '109 days',
    now() + interval '109 days 2 hours',
    null,
    false,
    false,
    null,
    now() - interval '1 day',
    '[{"id":"57555555-5555-5555-5555-555555555911","kind":"free-text","prompt":"What should the organizers know?","required":true,"options":[]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555922',
    'Registration Window Approval Future',
    'alpha-registration-window-approval-future',
    'Approval-required event whose registration window has not opened.',
    'Approval event with future registration.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '120 days',
    now() + interval '120 days 2 hours',
    null,
    false,
    true,
    now() + interval '1 day',
    now() + interval '30 days',
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555923',
    'Registration Window Price Ended',
    'alpha-registration-window-price-ended',
    'Ticket offer event whose only price window has ended.',
    'Ticket event with ended pricing.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '121 days',
    now() + interval '121 days 2 hours',
    null,
    false,
    true,
    null,
    null,
    '[]'::jsonb
);

-- Ticketing workflow fixtures for payment returns, offers, and request coverage.
insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, payment_currency_code, published,
    test_event, starts_at, ends_at, waitlist_enabled, attendee_approval_required,
    registration_questions
) values (
    '55555555-5555-5555-5555-555555555912',
    'Payment Return States Lab',
    'alpha-payment-return-states',
    'Paid event with confirmed and pending checkout return states.',
    'Payment return state coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '110 days',
    now() + interval '110 days 2 hours',
    false,
    false,
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555913',
    'Ticket Request Lab',
    'alpha-ticket-request-lab',
    'Approval-required paid event with public and invitation-only tickets.',
    'Public ticket request coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '111 days',
    now() + interval '111 days 2 hours',
    false,
    true,
    '[{"id":"57555555-5555-5555-5555-555555555913","kind":"free-text","prompt":"Why would you like this ticket?","required":true,"options":[]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555914',
    'Invitation Request Lifecycle Lab',
    'alpha-invitation-request-lifecycle',
    'Approval-required event with assignable private ticket tiers.',
    'Invitation request lifecycle coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '112 days',
    now() + interval '112 days 2 hours',
    false,
    true,
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555915',
    'No Assignable Invitation Tier Lab',
    'alpha-no-assignable-invitation-tier',
    'Approval-required event without an assignable private ticket tier.',
    'Unavailable private tier coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '113 days',
    now() + interval '113 days 2 hours',
    false,
    true,
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555916',
    'Paid Event Offers Lab',
    'alpha-paid-event-offers',
    'Paid private-ticket event with pending and checkout-started offers.',
    'Paid dashboard offer coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '114 days',
    now() + interval '114 days 2 hours',
    false,
    false,
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555917',
    'Paid Registration Questions Lab',
    'alpha-paid-registration-questions',
    'Paid ticket event that collects registration answers before checkout.',
    'Paid registration question coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '115 days',
    now() + interval '115 days 2 hours',
    false,
    false,
    '[{"id":"57555555-5555-5555-5555-555555555917","kind":"free-text","prompt":"What should the organizers prepare for you?","required":true,"options":[]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555918',
    'Sold Out Ticket States Lab',
    'alpha-sold-out-ticket-states',
    'Ticketed event with a sold-out public tier and waiting list.',
    'Sold-out ticket and waitlist coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '116 days',
    now() + interval '116 days 2 hours',
    true,
    false,
    '[{"id":"57555555-5555-5555-5555-555555555918","kind":"free-text","prompt":"What would you like to learn?","required":true,"options":[]}]'::jsonb
), (
    '55555555-5555-5555-5555-555555555919',
    'Migrated Unlimited Capacity Event',
    'alpha-migrated-unlimited-capacity',
    'Event shaped like an unlimited-capacity event after ticket migration.',
    'Migration-shaped ticket capacity coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    null,
    true,
    true,
    now() + interval '117 days',
    now() + interval '117 days 2 hours',
    false,
    false,
    '[]'::jsonb
);

insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, payment_currency_code, published,
    test_event, starts_at, ends_at, capacity, waitlist_enabled,
    attendee_approval_required, registration_questions
) values (
    '55555555-5555-5555-5555-555555555920',
    'Refunded Capacity Release Lab',
    'alpha-refunded-capacity-release',
    'One-seat paid event whose finalized refund released its capacity.',
    'Finalized refund capacity coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '118 days',
    now() + interval '118 days 2 hours',
    1,
    false,
    false,
    '[]'::jsonb
);

insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, payment_currency_code, published,
    test_event, starts_at, ends_at, capacity, waitlist_enabled,
    attendee_approval_required, registration_questions, external_payment_url,
    external_payment_instructions, external_payment_window_hours, location,
    venue_address, venue_city, venue_country_code, venue_country_name, venue_name,
    venue_state_code, venue_state_name, venue_zip_code
) values (
    '55555555-5555-5555-5555-555555555924',
    'External Payment Lifecycle Lab',
    'external-payment-lifecycle',
    'External payment event used for registration, confirmation, and refund coverage.',
    'External payment lifecycle coverage.',
    'America/New_York',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444448',
    'USD',
    true,
    true,
    now() + interval '120 days',
    now() + interval '120 days 2 hours',
    8,
    false,
    false,
    '[]'::jsonb,
    'https://payments.example.com/external-lifecycle',
    'Include the reservation reference with the bank transfer.',
    72,
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    '123 Payment Way',
    'New York',
    'US',
    'United States',
    'External Payment Hall',
    'NY',
    'New York',
    '10001'
), (
    '55555555-5555-5555-5555-555555555925',
    'External Payment Capacity Lab',
    'external-payment-capacity',
    'One-seat external payment event used for capacity race coverage.',
    'External payment capacity coverage.',
    'America/New_York',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444448',
    'USD',
    true,
    true,
    now() + interval '121 days',
    now() + interval '121 days 2 hours',
    1,
    false,
    false,
    '[]'::jsonb,
    'https://payments.example.com/external-capacity',
    'Complete payment before the reservation expires.',
    24,
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    '123 Payment Way',
    'New York',
    'US',
    'United States',
    'External Payment Hall',
    'NY',
    'New York',
    '10001'
), (
    '55555555-5555-5555-5555-555555555926',
    'External Payment Invitation Lab',
    'external-payment-invitation',
    'Invitation-only external payment event used for offer claim coverage.',
    'External payment invitation coverage.',
    'America/New_York',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444448',
    'USD',
    true,
    true,
    now() + interval '122 days',
    now() + interval '122 days 2 hours',
    2,
    false,
    false,
    '[]'::jsonb,
    'https://payments.example.com/external-invitation',
    'Use the invitation reference when sending payment.',
    48,
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    '123 Payment Way',
    'New York',
    'US',
    'United States',
    'External Payment Hall',
    'NY',
    'New York',
    '10001'
), (
    '55555555-5555-5555-5555-555555555927',
    'External Payment Free Ticket Lab',
    'external-payment-free-ticket-lab',
    'Free event used to verify copied external payment fields are cleared.',
    'Free event copy coverage.',
    'America/New_York',
    '33333333-3333-3333-3333-333333333331',
    'hybrid',
    '44444444-4444-4444-4444-444444444448',
    null,
    true,
    true,
    now() + interval '123 days',
    now() + interval '123 days 2 hours',
    8,
    false,
    false,
    '[]'::jsonb,
    null,
    null,
    null,
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    '123 Payment Way',
    'New York',
    'US',
    'United States',
    'External Payment Hall',
    'NY',
    'New York',
    '10001'
);

update event
set
    event_kind_id = case
        when event_id = '55555555-5555-5555-5555-555555555507' then 'in-person'
        else 'hybrid'
    end,
    location = ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    payment_currency_code = 'USD',
    venue_address = '123 Payment Way',
    venue_city = case
        when event_id = '55555555-5555-5555-5555-555555555507' then 'Chicago'
        else 'New York'
    end,
    venue_country_code = 'US',
    venue_country_name = 'United States',
    venue_name = 'E2E Admission Hall',
    venue_state_code = case
        when event_id = '55555555-5555-5555-5555-555555555507' then 'IL'
        else 'NY'
    end,
    venue_state_name = case
        when event_id = '55555555-5555-5555-5555-555555555507' then 'IL'
        else 'NY'
    end,
    venue_zip_code = case
        when event_id = '55555555-5555-5555-5555-555555555507' then '60601'
        else '10001'
    end
where event_id in (
    '55555555-5555-5555-5555-555555555506',
    '55555555-5555-5555-5555-555555555507',
    '55555555-5555-5555-5555-555555555522',
    '55555555-5555-5555-5555-555555555523',
    '55555555-5555-5555-5555-555555555901',
    '55555555-5555-5555-5555-555555555902',
    '55555555-5555-5555-5555-555555555903',
    '55555555-5555-5555-5555-555555555911',
    '55555555-5555-5555-5555-555555555912',
    '55555555-5555-5555-5555-555555555913',
    '55555555-5555-5555-5555-555555555914',
    '55555555-5555-5555-5555-555555555916',
    '55555555-5555-5555-5555-555555555917',
    '55555555-5555-5555-5555-555555555918',
    '55555555-5555-5555-5555-555555555920'
);

-- Calendar navigation fixtures (dates relative to now())
insert into event (
    event_id, name, slug, description, description_short, timezone, event_category_id,
    event_kind_id, group_id, published, starts_at, ends_at,
    venue_name, venue_address, venue_city, venue_state_code, venue_state_name, venue_country_name,
    venue_country_code, venue_zip_code, location, banner_url, logo_url, capacity,
    tags, meetup_url, meeting_join_url, photos_urls
) values (
    '55555555-5555-5555-5555-555555555937',
    'Alpha Calendar This Month',
    'alpha-calendar-this-month',
    'Current-month event used for explore calendar navigation coverage.',
    'Current-month calendar coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'in-person',
    '44444444-4444-4444-4444-444444444441',
    true,
    date_trunc('month', now()) + interval '14 days 10 hours',
    date_trunc('month', now()) + interval '14 days 12 hours',
    'Tech Conference Center',
    '123 Main Street',
    'New York',
    'NY',
    'NY',
    'United States',
    'US',
    '10001',
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    '/static/images/e2e/event-banner.svg',
    '/static/images/e2e/event-logo.svg',
    100,
    '{"meetup", "tech", "calendar"}',
    'https://www.meetup.com/test-group/events/555555937/',
    'https://zoom.us/j/5555559370',
    '{"/static/images/e2e/missing-event-gallery-photo.svg", "/static/images/e2e/event-photo-2.svg"}'
), (
    '55555555-5555-5555-5555-555555555938',
    'Alpha Calendar Next Month',
    'alpha-calendar-next-month',
    'Next-month event used for explore calendar navigation coverage.',
    'Next-month calendar coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'in-person',
    '44444444-4444-4444-4444-444444444441',
    true,
    date_trunc('month', now()) + interval '1 month' + interval '14 days 10 hours',
    date_trunc('month', now()) + interval '1 month' + interval '14 days 12 hours',
    'Tech Conference Center',
    '123 Main Street',
    'New York',
    'NY',
    'NY',
    'United States',
    'US',
    '10001',
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    '/static/images/e2e/event-banner.svg',
    '/static/images/e2e/event-logo.svg',
    100,
    '{"meetup", "tech", "calendar"}',
    'https://www.meetup.com/test-group/events/555555938/',
    'https://zoom.us/j/5555559380',
    '{"/static/images/e2e/missing-event-gallery-photo.svg", "/static/images/e2e/event-photo-2.svg"}'
);

-- Meeting webhook fixtures
insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, published, test_event,
    starts_at, ends_at, capacity, meeting_provider_id, meeting_requested,
    meeting_in_sync, meeting_error, meeting_recording_published,
    meeting_recording_url, meeting_sync_claimed_at
) values (
    '55555555-5555-5555-5555-555555555943',
    'Zoom Recording Webhook Lab',
    'alpha-zoom-recording',
    'Past automatic Zoom event used for recording webhook coverage.',
    'Zoom recording webhook coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    now() - interval '2 days',
    now() - interval '2 days' + interval '2 hours',
    100,
    'zoom',
    true,
    true,
    null,
    false,
    null,
    null
), (
    '55555555-5555-5555-5555-555555555944',
    'Zoom Live Join Lab',
    'alpha-zoom-live',
    'Live automatic Zoom event used for attendee meeting-link coverage.',
    'Zoom live join-link coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    now() + interval '5 minutes',
    now() + interval '7 days',
    100,
    'zoom',
    true,
    true,
    null,
    false,
    null,
    null
), (
    '55555555-5555-5555-5555-555555555945',
    'Zoom Pending Sync Lab',
    'alpha-zoom-pending',
    'Future automatic Zoom event with an in-flight provider sync claim.',
    'Zoom pending sync coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    now() + interval '140 days',
    now() + interval '140 days 2 hours',
    100,
    'zoom',
    true,
    false,
    null,
    false,
    null,
    current_timestamp
), (
    '55555555-5555-5555-5555-555555555946',
    'Zoom Error Sync Lab',
    'alpha-zoom-error',
    'Future automatic Zoom event with a terminal provider sync error.',
    'Zoom error state coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    now() + interval '141 days',
    now() + interval '141 days 2 hours',
    100,
    'zoom',
    true,
    true,
    'Zoom returned rate limit during provisioning.',
    false,
    null,
    null
), (
    '55555555-5555-5555-5555-555555555947',
    'Zoom Public Recording Lab',
    'alpha-zoom-public-recording',
    'Past automatic Zoom event with a published public recording link.',
    'Zoom public recording coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    now() - interval '3 days',
    now() - interval '3 days' + interval '2 hours',
    100,
    'zoom',
    true,
    true,
    null,
    true,
    'https://recordings.example.test/alpha-zoom-public-recording',
    null
), (
    '55555555-5555-5555-5555-555555555948',
    'Zoom Unpublished Recording Lab',
    'alpha-zoom-unpublished-recording',
    'Past automatic Zoom event with an unpublished final recording link.',
    'Zoom unpublished recording coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    true,
    true,
    now() - interval '4 days',
    now() - interval '4 days' + interval '2 hours',
    100,
    'zoom',
    true,
    true,
    null,
    false,
    'https://recordings.example.test/alpha-zoom-unpublished-recording',
    null
);

-- Stripe webhook fixtures
insert into event (
    event_id, name, slug, description, description_short, timezone,
    event_category_id, event_kind_id, group_id, payment_currency_code, published,
    test_event, starts_at, ends_at, capacity, waitlist_enabled,
    attendee_approval_required, registration_questions
) values (
    '55555555-5555-5555-5555-555555555940',
    'Stripe Webhook Expire Lab',
    'alpha-webhook-expire',
    'Paid event with an active checkout hold for Stripe expiration webhook coverage.',
    'Stripe expiration webhook coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '124 days',
    now() + interval '124 days 2 hours',
    2,
    false,
    false,
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555941',
    'Stripe Webhook Invoice Lab',
    'alpha-webhook-invoice',
    'Paid event with a completed purchase awaiting a Stripe invoice webhook.',
    'Stripe invoice webhook coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '125 days',
    now() + interval '125 days 2 hours',
    4,
    false,
    false,
    '[]'::jsonb
), (
    '55555555-5555-5555-5555-555555555942',
    'Stripe Webhook Refund Lab',
    'alpha-webhook-refund',
    'Paid event with a provider-pending refund for Stripe refund webhook coverage.',
    'Stripe refund webhook coverage.',
    'UTC',
    '33333333-3333-3333-3333-333333333331',
    'virtual',
    '44444444-4444-4444-4444-444444444441',
    'USD',
    true,
    true,
    now() + interval '126 days',
    now() + interval '126 days 2 hours',
    1,
    false,
    false,
    '[]'::jsonb
);
