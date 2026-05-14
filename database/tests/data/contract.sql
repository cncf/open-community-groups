begin;

-- ============================================================================
-- COMMUNITIES
-- ============================================================================

insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.com/community-banner-mobile.png',
    'https://example.com/community-banner.png',
    '00000000-0000-0000-0000-00000000c001',
    'A community used by Rust database contract tests',
    'Contract Community',
    'https://example.com/community-logo.png',
    'contract-community'
);

-- ============================================================================
-- USERS
-- ============================================================================

insert into "user" (
    auth_hash,
    bio,
    company,
    email,
    email_verified,
    github_url,
    name,
    photo_url,
    provider,
    title,
    user_id,
    username,
    website_url
) values
    (
        'contract_hash_organizer',
        'Builds reliable community platforms',
        'Open Community Groups',
        'organizer.contract@example.com',
        true,
        'https://github.com/contract-organizer',
        'Contract Organizer',
        'https://example.com/organizer.png',
        '{"github": {"username": "contract-organizer"}}'::jsonb,
        'Organizer',
        '00000000-0000-0000-0000-00000000c041',
        'contract-organizer',
        'https://example.com/organizer'
    ),
    (
        'contract_hash_attendee',
        'Attends contract test events',
        'Open Community Groups',
        'attendee.contract@example.com',
        true,
        'https://github.com/contract-attendee',
        'Contract Attendee',
        'https://example.com/attendee.png',
        '{"github": {"username": "contract-attendee"}}'::jsonb,
        'Attendee',
        '00000000-0000-0000-0000-00000000c042',
        'contract-attendee',
        'https://example.com/attendee'
    ),
    (
        'contract_hash_waitlist',
        'Waits for contract test events',
        'Open Community Groups',
        'waitlist.contract@example.com',
        true,
        'https://github.com/contract-waitlist',
        'Contract Waitlist',
        'https://example.com/waitlist.png',
        '{"github": {"username": "contract-waitlist"}}'::jsonb,
        'Waitlisted attendee',
        '00000000-0000-0000-0000-00000000c043',
        'contract-waitlist',
        'https://example.com/waitlist'
    );

-- ============================================================================
-- REGIONS
-- ============================================================================

insert into region (
    community_id,
    name,
    region_id
) values (
    '00000000-0000-0000-0000-00000000c001',
    'North America',
    '00000000-0000-0000-0000-00000000c011'
);

-- ============================================================================
-- GROUP CATEGORIES
-- ============================================================================

insert into group_category (
    community_id,
    group_category_id,
    name
) values (
    '00000000-0000-0000-0000-00000000c001',
    '00000000-0000-0000-0000-00000000c012',
    'Technology'
);

-- ============================================================================
-- EVENT CATEGORIES
-- ============================================================================

insert into event_category (
    community_id,
    event_category_id,
    name
) values (
    '00000000-0000-0000-0000-00000000c001',
    '00000000-0000-0000-0000-00000000c013',
    'Conference'
);

-- ============================================================================
-- GROUPS
-- ============================================================================

insert into "group" (
    banner_mobile_url,
    banner_url,
    city,
    community_id,
    country_code,
    country_name,
    created_at,
    description,
    description_short,
    group_category_id,
    group_id,
    location,
    logo_url,
    name,
    payment_recipient,
    photos_urls,
    region_id,
    slug,
    state,
    tags,
    website_url
) values (
    'https://example.com/group-banner-mobile.png',
    'https://example.com/group-banner.png',
    'San Francisco',
    '00000000-0000-0000-0000-00000000c001',
    'US',
    'United States',
    '2024-01-01 10:00:00+00',
    'A group used by Rust database contract tests',
    'Rust database contract group',
    '00000000-0000-0000-0000-00000000c012',
    '00000000-0000-0000-0000-00000000c021',
    ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326),
    'https://example.com/group-logo.png',
    'Contract Group',
    '{"provider":"stripe","recipient_id":"acct_contract_group"}'::jsonb,
    array['https://example.com/group-photo.png'],
    '00000000-0000-0000-0000-00000000c011',
    'contract-group',
    'CA',
    array['rust', 'database', 'contracts'],
    'https://example.com/group'
);

-- ============================================================================
-- GROUP MEMBERS
-- ============================================================================

insert into group_member (
    group_id,
    user_id
) values (
    '00000000-0000-0000-0000-00000000c021',
    '00000000-0000-0000-0000-00000000c042'
);

-- ============================================================================
-- GROUP TEAM
-- ============================================================================

insert into group_team (
    accepted,
    group_id,
    role,
    user_id,
    "order"
) values (
    true,
    '00000000-0000-0000-0000-00000000c021',
    'admin',
    '00000000-0000-0000-0000-00000000c041',
    1
);

-- ============================================================================
-- GROUP SPONSORS
-- ============================================================================

insert into group_sponsor (
    featured,
    group_id,
    group_sponsor_id,
    logo_url,
    name,
    website_url
) values (
    true,
    '00000000-0000-0000-0000-00000000c021',
    '00000000-0000-0000-0000-00000000c061',
    'https://example.com/sponsor-logo.png',
    'Contract Sponsor',
    'https://example.com/sponsor'
);

-- ============================================================================
-- EVENTS
-- ============================================================================

insert into event (
    banner_mobile_url,
    banner_url,
    capacity,
    created_at,
    created_by,
    description,
    description_short,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    location,
    logo_url,
    name,
    payment_currency_code,
    photos_urls,
    published,
    published_at,
    registration_required,
    slug,
    starts_at,
    tags,
    timezone,
    venue_address,
    venue_city,
    venue_country_code,
    venue_country_name,
    venue_name,
    venue_state,
    venue_zip_code,
    waitlist_enabled
) values
    (
        'https://example.com/future-event-banner-mobile.png',
        'https://example.com/future-event-banner.png',
        100,
        '2024-01-02 10:00:00+00',
        '00000000-0000-0000-0000-00000000c041',
        'A future event used by Rust database contract tests',
        'Future contract event',
        '2099-05-20 19:00:00+00',
        '00000000-0000-0000-0000-00000000c013',
        '00000000-0000-0000-0000-00000000c031',
        'hybrid',
        '00000000-0000-0000-0000-00000000c021',
        ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326),
        'https://example.com/future-event-logo.png',
        'Future Contract Event',
        'USD',
        array['https://example.com/future-event-photo.png'],
        true,
        '2024-01-03 10:00:00+00',
        true,
        'future-contract-event',
        '2099-05-20 17:00:00+00',
        array['rust', 'contract'],
        'America/Los_Angeles',
        '1 Contract Way',
        'San Francisco',
        'US',
        'United States',
        'Contract Hall',
        'CA',
        '94105',
        true
    ),
    (
        'https://example.com/past-event-banner-mobile.png',
        'https://example.com/past-event-banner.png',
        50,
        '2024-01-04 10:00:00+00',
        '00000000-0000-0000-0000-00000000c041',
        'A past event used by Rust database contract tests',
        'Past contract event',
        '2000-05-20 19:00:00+00',
        '00000000-0000-0000-0000-00000000c013',
        '00000000-0000-0000-0000-00000000c032',
        'virtual',
        '00000000-0000-0000-0000-00000000c021',
        ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326),
        'https://example.com/past-event-logo.png',
        'Past Contract Event',
        null,
        array['https://example.com/past-event-photo.png'],
        true,
        '2024-01-05 10:00:00+00',
        true,
        'past-contract-event',
        '2000-05-20 17:00:00+00',
        array['rust', 'contract'],
        'UTC',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        false
    );

-- ============================================================================
-- MEETING CLAIM GROUPS
-- ============================================================================

insert into "group" (
    active,
    community_id,
    description,
    group_category_id,
    group_id,
    name,
    slug
) values (
    false,
    '00000000-0000-0000-0000-00000000c001',
    'A private group used by Rust meeting claim contract tests',
    '00000000-0000-0000-0000-00000000c012',
    '00000000-0000-0000-0000-00000000c0a0',
    'Contract Meeting Claim Group',
    'contract-meeting-claim-group'
);

-- ============================================================================
-- MEETING CLAIM CANDIDATES
-- ============================================================================

insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    published,
    slug,
    starts_at,
    timezone
) values
    (
        100,
        'A meeting sync event used by Rust database contract tests',
        '2099-06-01 11:00:00+00',
        '00000000-0000-0000-0000-00000000c013',
        '00000000-0000-0000-0000-00000000c0a1',
        'virtual',
        '00000000-0000-0000-0000-00000000c0a0',
        false,
        'zoom',
        true,
        'Contract Meeting Sync Event',
        true,
        'contract-meeting-sync-event',
        '2099-06-01 10:00:00+00',
        'UTC'
    ),
    (
        100,
        'An auto-end event used by Rust database contract tests',
        '2000-06-01 11:00:00+00',
        '00000000-0000-0000-0000-00000000c013',
        '00000000-0000-0000-0000-00000000c0a2',
        'virtual',
        '00000000-0000-0000-0000-00000000c0a0',
        true,
        'zoom',
        true,
        'Contract Auto End Event',
        true,
        'contract-auto-end-event',
        '2000-06-01 10:00:00+00',
        'UTC'
    );

insert into meeting (
    event_id,
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id
) values (
    '00000000-0000-0000-0000-00000000c0a2',
    'https://zoom.us/j/contract-auto-end',
    '00000000-0000-0000-0000-00000000c0a3',
    'zoom',
    'contract-auto-end'
);

-- ============================================================================
-- EVENT ATTENDEES
-- ============================================================================

insert into event_attendee (
    checked_in,
    checked_in_at,
    event_id,
    user_id
) values (
    true,
    '2099-05-20 17:30:00+00',
    '00000000-0000-0000-0000-00000000c031',
    '00000000-0000-0000-0000-00000000c042'
);

-- ============================================================================
-- EVENT WAITLIST
-- ============================================================================

insert into event_waitlist (
    event_id,
    user_id
) values (
    '00000000-0000-0000-0000-00000000c031',
    '00000000-0000-0000-0000-00000000c043'
);

-- ============================================================================
-- EVENT INVITATION REQUESTS
-- ============================================================================

insert into event_invitation_request (
    created_at,
    event_id,
    status,
    user_id
) values (
    '2024-01-08 10:00:00+00',
    '00000000-0000-0000-0000-00000000c031',
    'pending',
    '00000000-0000-0000-0000-00000000c043'
);

-- ============================================================================
-- EVENT HOSTS
-- ============================================================================

insert into event_host (
    event_id,
    user_id
) values (
    '00000000-0000-0000-0000-00000000c031',
    '00000000-0000-0000-0000-00000000c041'
);

-- ============================================================================
-- EVENT SPEAKERS
-- ============================================================================

insert into event_speaker (
    event_id,
    featured,
    user_id
) values (
    '00000000-0000-0000-0000-00000000c031',
    true,
    '00000000-0000-0000-0000-00000000c041'
);

-- ============================================================================
-- EVENT SPONSORS
-- ============================================================================

insert into event_sponsor (
    event_id,
    group_sponsor_id,
    level
) values (
    '00000000-0000-0000-0000-00000000c031',
    '00000000-0000-0000-0000-00000000c061',
    'Gold'
);

-- ============================================================================
-- SESSIONS
-- ============================================================================

insert into session (
    description,
    ends_at,
    event_id,
    location,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    'A session used by Rust database contract tests',
    '2099-05-20 18:00:00+00',
    '00000000-0000-0000-0000-00000000c031',
    'Room 1',
    'Contract Session',
    '00000000-0000-0000-0000-00000000c051',
    'hybrid',
    '2099-05-20 17:15:00+00'
);

-- ============================================================================
-- SESSION SPEAKERS
-- ============================================================================

insert into session_speaker (
    featured,
    session_id,
    user_id
) values (
    true,
    '00000000-0000-0000-0000-00000000c051',
    '00000000-0000-0000-0000-00000000c041'
);

-- ============================================================================
-- EVENT TICKETING
-- ============================================================================

insert into event_ticket_type (
    active,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    true,
    '00000000-0000-0000-0000-00000000c031',
    '00000000-0000-0000-0000-00000000c081',
    1,
    100,
    'General Admission'
);

insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values (
    2500,
    '00000000-0000-0000-0000-00000000c082',
    '00000000-0000-0000-0000-00000000c081'
);

-- ============================================================================
-- PAGE VIEWS
-- ============================================================================

insert into group_views (
    day,
    group_id,
    total
) values (
    current_date,
    '00000000-0000-0000-0000-00000000c021',
    3
);

insert into event_views (
    day,
    event_id,
    total
) values (
    current_date,
    '00000000-0000-0000-0000-00000000c031',
    2
);

-- ============================================================================
-- AUDIT LOGS
-- ============================================================================

insert into audit_log (
    action,
    actor_user_id,
    actor_username,
    audit_log_id,
    community_id,
    created_at,
    details,
    group_id,
    resource_id,
    resource_type
) values (
    'group_payment_recipient_updated',
    '00000000-0000-0000-0000-00000000c041',
    'contract-organizer',
    '00000000-0000-0000-0000-00000000c091',
    '00000000-0000-0000-0000-00000000c001',
    '2024-01-09 10:00:00+00',
    '{"recipient_id":"acct_contract_group"}'::jsonb,
    '00000000-0000-0000-0000-00000000c021',
    '00000000-0000-0000-0000-00000000c021',
    'group'
);

commit;
