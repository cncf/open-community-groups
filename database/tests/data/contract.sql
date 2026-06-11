begin;

-- ============================================================================
-- SITE
-- ============================================================================

insert into site (
    description,
    site_id,
    theme,
    title,

    copyright_notice,
    favicon_url,
    footer_logo_url,
    header_logo_url,
    og_image_url
) values (
    'A site used by Rust database contract tests',
    '00000000-0000-0000-0000-00000000c0b1',
    '{"palette": {"50": "#eff6ff", "900": "#1e3a8a"}, "primary_color": "#0066cc"}'::jsonb,
    'Contract Site',
    'Copyright Contract Site',
    'https://example.com/favicon.ico',
    'https://example.com/footer-logo.png',
    'https://example.com/header-logo.png',
    'https://example.com/site-og-image.png'
);

-- ============================================================================
-- COMMUNITIES
-- ============================================================================

insert into community (
    ad_banner_link_url,
    ad_banner_url,
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.com/community-ad',
    'https://example.com/community-ad-banner.png',
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
    password,
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
        'contract_password_hash',
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
        null,
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
        null,
        'https://example.com/waitlist.png',
        '{"github": {"username": "contract-waitlist"}}'::jsonb,
        'Waitlisted attendee',
        '00000000-0000-0000-0000-00000000c043',
        'contract-waitlist',
        'https://example.com/waitlist'
    );

insert into "user" (
    auth_hash,
    email,
    email_verified,
    registration_status,
    user_id,
    username
) values
    (
        'contract_hash_pre_registered',
        'pre-registered.contract@example.com',
        false,
        'pre-registered',
        '00000000-0000-0000-0000-00000000c044',
        'invited-5cd4f396e5e9cc2d07ebc0a5'
    ),
    (
        'contract_hash_activation',
        'activation.contract@example.com',
        false,
        'pre-registered',
        '00000000-0000-0000-0000-00000000c045',
        'invited-7ab2e187f4d3bb1c96fda1b4'
    );

insert into "user" (
    auth_hash,
    email,
    email_verified,
    name,
    user_id,
    username
) values
    (
        'contract_hash_buyer_checkout',
        'buyer-checkout.contract@example.com',
        true,
        'Contract Buyer Checkout',
        '00000000-0000-0000-0000-00000000c0e1',
        'contract-buyer-checkout'
    ),
    (
        'contract_hash_buyer_summary',
        'buyer-summary.contract@example.com',
        true,
        'Contract Buyer Summary',
        '00000000-0000-0000-0000-00000000c0e2',
        'contract-buyer-summary'
    ),
    (
        'contract_hash_buyer_reconcile',
        'buyer-reconcile.contract@example.com',
        true,
        'Contract Buyer Reconcile',
        '00000000-0000-0000-0000-00000000c0e3',
        'contract-buyer-reconcile'
    ),
    (
        'contract_hash_buyer_free',
        'buyer-free.contract@example.com',
        true,
        'Contract Buyer Free',
        '00000000-0000-0000-0000-00000000c0e4',
        'contract-buyer-free'
    ),
    (
        'contract_hash_buyer_refund_begin',
        'buyer-refund-begin.contract@example.com',
        true,
        'Contract Buyer Refund Begin',
        '00000000-0000-0000-0000-00000000c0e5',
        'contract-buyer-refund-begin'
    ),
    (
        'contract_hash_buyer_refund_approve',
        'buyer-refund-approve.contract@example.com',
        true,
        'Contract Buyer Refund Approve',
        '00000000-0000-0000-0000-00000000c0e6',
        'contract-buyer-refund-approve'
    ),
    (
        'contract_hash_buyer_refund_reject',
        'buyer-refund-reject.contract@example.com',
        true,
        'Contract Buyer Refund Reject',
        '00000000-0000-0000-0000-00000000c0e7',
        'contract-buyer-refund-reject'
    ),
    (
        'contract_hash_leaver',
        'leaver.contract@example.com',
        true,
        'Contract Leaver',
        '00000000-0000-0000-0000-00000000c0e8',
        'contract-leaver'
    ),
    (
        'contract_hash_cancelee',
        'cancelee.contract@example.com',
        true,
        'Contract Cancelee',
        '00000000-0000-0000-0000-00000000c0e9',
        'contract-cancelee'
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
-- COMMUNITY TEAM
-- ============================================================================

insert into community_team (
    accepted,
    community_id,
    created_at,
    role,
    user_id
) values
    (
        true,
        '00000000-0000-0000-0000-00000000c001',
        '2024-01-06 10:00:00+00',
        'admin',
        '00000000-0000-0000-0000-00000000c041'
    ),
    (
        false,
        '00000000-0000-0000-0000-00000000c001',
        '2024-01-07 10:00:00+00',
        'viewer',
        '00000000-0000-0000-0000-00000000c043'
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
    luma_url,
    name,
    payment_currency_code,
    photos_urls,
    published,
    published_at,
    registration_required,
    registration_questions,
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
        'https://luma.com/contract-event',
        'Future Contract Event',
        'USD',
        array['https://example.com/future-event-photo.png'],
        true,
        '2024-01-03 10:00:00+00',
        true,
        '[{"id": "00000000-0000-0000-0000-00000000c071", "kind": "single-select", "prompt": "Meal preference", "required": true, "options": [{"id": "00000000-0000-0000-0000-00000000c072", "label": "Vegetarian"}]}]'::jsonb,
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
        null,
        'Past Contract Event',
        null,
        array['https://example.com/past-event-photo.png'],
        true,
        '2024-01-05 10:00:00+00',
        true,
        '[]'::jsonb,
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

-- Pending group team invitation (claim group)
insert into group_team (
    accepted,
    created_at,
    group_id,
    role,
    user_id
) values (
    false,
    '2024-01-07 10:00:00+00',
    '00000000-0000-0000-0000-00000000c0a0',
    'viewer',
    '00000000-0000-0000-0000-00000000c042'
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
    registration_answers,
    user_id
) values (
    true,
    '2099-05-20 17:30:00+00',
    '00000000-0000-0000-0000-00000000c031',
    '{"answers": [{"question_id": "00000000-0000-0000-0000-00000000c071", "value": "00000000-0000-0000-0000-00000000c072"}]}'::jsonb,
    '00000000-0000-0000-0000-00000000c042'
);

insert into event_attendee (
    event_id,
    manually_invited,
    status,
    user_id
) values (
    '00000000-0000-0000-0000-00000000c031',
    true,
    'invitation-pending',
    '00000000-0000-0000-0000-00000000c044'
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
-- EVENT ORGANIZERS
-- ============================================================================

insert into event_organizer (event_id, user_id, "order")
select e.event_id, gt.user_id, gt."order"
from event e
join group_team gt on gt.group_id = e.group_id
where e.legacy_id is null
and gt.accepted = true;

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
-- EVENT PURCHASES
-- ============================================================================

-- Events in this section use test_event = true so public stats and search
-- results stay unchanged when mutation tests add or remove attendees. Each
-- purchase and refund request row is dedicated to a single mutation test.
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    test_event,
    timezone
) values (
    100,
    'A ticketed event used by Rust database contract tests',
    '2099-07-01 11:00:00+00',
    '00000000-0000-0000-0000-00000000c013',
    '00000000-0000-0000-0000-00000000c0d0',
    'virtual',
    '00000000-0000-0000-0000-00000000c021',
    'Contract Ticketed Event',
    'USD',
    true,
    'contract-ticketed-event',
    '2099-07-01 10:00:00+00',
    true,
    'UTC'
);

insert into event_ticket_type (
    active,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values
    (
        true,
        '00000000-0000-0000-0000-00000000c0d0',
        '00000000-0000-0000-0000-00000000c0d1',
        1,
        50,
        'Contract Paid Ticket'
    ),
    (
        true,
        '00000000-0000-0000-0000-00000000c0d0',
        '00000000-0000-0000-0000-00000000c0d3',
        2,
        50,
        'Contract Free Ticket'
    );

insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values
    (
        2500,
        '00000000-0000-0000-0000-00000000c0d2',
        '00000000-0000-0000-0000-00000000c0d1'
    ),
    (
        0,
        '00000000-0000-0000-0000-00000000c0d4',
        '00000000-0000-0000-0000-00000000c0d3'
    );

-- Confirmed attendees backing the refund request purchases below
insert into event_attendee (
    event_id,
    user_id
) values
    ('00000000-0000-0000-0000-00000000c0d0', '00000000-0000-0000-0000-00000000c0e5'),
    ('00000000-0000-0000-0000-00000000c0d0', '00000000-0000-0000-0000-00000000c0e6'),
    ('00000000-0000-0000-0000-00000000c0d0', '00000000-0000-0000-0000-00000000c0e7');

insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,
    completed_at,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_payment_reference
) values
    (
        2500,
        'USD',
        '00000000-0000-0000-0000-00000000c0d0',
        '00000000-0000-0000-0000-00000000c0f1',
        '00000000-0000-0000-0000-00000000c0d1',
        'pending',
        'Contract Paid Ticket',
        '00000000-0000-0000-0000-00000000c0e2',
        null,
        '2099-01-01 00:00:00+00',
        null,
        null,
        null
    ),
    (
        2500,
        'USD',
        '00000000-0000-0000-0000-00000000c0d0',
        '00000000-0000-0000-0000-00000000c0f2',
        '00000000-0000-0000-0000-00000000c0d1',
        'pending',
        'Contract Paid Ticket',
        '00000000-0000-0000-0000-00000000c0e3',
        null,
        '2099-01-01 00:00:00+00',
        'stripe',
        'cs_contract_reconcile',
        null
    ),
    (
        0,
        'USD',
        '00000000-0000-0000-0000-00000000c0d0',
        '00000000-0000-0000-0000-00000000c0f3',
        '00000000-0000-0000-0000-00000000c0d3',
        'pending',
        'Contract Free Ticket',
        '00000000-0000-0000-0000-00000000c0e4',
        null,
        '2099-01-01 00:00:00+00',
        null,
        null,
        null
    ),
    (
        2500,
        'USD',
        '00000000-0000-0000-0000-00000000c0d0',
        '00000000-0000-0000-0000-00000000c0f4',
        '00000000-0000-0000-0000-00000000c0d1',
        'refund-requested',
        'Contract Paid Ticket',
        '00000000-0000-0000-0000-00000000c0e5',
        '2024-02-01 10:00:00+00',
        null,
        'stripe',
        'cs_contract_refund_begin',
        'pi_contract_refund_begin'
    ),
    (
        2500,
        'USD',
        '00000000-0000-0000-0000-00000000c0d0',
        '00000000-0000-0000-0000-00000000c0f6',
        '00000000-0000-0000-0000-00000000c0d1',
        'refund-requested',
        'Contract Paid Ticket',
        '00000000-0000-0000-0000-00000000c0e6',
        '2024-02-01 10:00:00+00',
        null,
        'stripe',
        'cs_contract_refund_approve',
        'pi_contract_refund_approve'
    ),
    (
        2500,
        'USD',
        '00000000-0000-0000-0000-00000000c0d0',
        '00000000-0000-0000-0000-00000000c0f8',
        '00000000-0000-0000-0000-00000000c0d1',
        'refund-requested',
        'Contract Paid Ticket',
        '00000000-0000-0000-0000-00000000c0e7',
        '2024-02-01 10:00:00+00',
        null,
        'stripe',
        'cs_contract_refund_reject',
        'pi_contract_refund_reject'
    );

insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    requested_reason,
    status
) values
    (
        '00000000-0000-0000-0000-00000000c0f4',
        '00000000-0000-0000-0000-00000000c0f5',
        '00000000-0000-0000-0000-00000000c0e5',
        'Cannot attend anymore',
        'pending'
    ),
    (
        '00000000-0000-0000-0000-00000000c0f6',
        '00000000-0000-0000-0000-00000000c0f7',
        '00000000-0000-0000-0000-00000000c0e6',
        'Cannot attend anymore',
        'approving'
    ),
    (
        '00000000-0000-0000-0000-00000000c0f8',
        '00000000-0000-0000-0000-00000000c0f9',
        '00000000-0000-0000-0000-00000000c0e7',
        'Cannot attend anymore',
        'pending'
    );

-- ============================================================================
-- EVENT MUTATIONS
-- ============================================================================

-- Unticketed test_event with dedicated attendees for the leave, cancel
-- attendance, and update event mutation tests.
insert into event (
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    test_event,
    timezone
) values (
    100,
    'A mutation event used by Rust database contract tests',
    '2099-08-01 11:00:00+00',
    '00000000-0000-0000-0000-00000000c013',
    '00000000-0000-0000-0000-00000000c0d5',
    'virtual',
    '00000000-0000-0000-0000-00000000c021',
    'Contract Mutation Event',
    true,
    'contract-mutation-event',
    '2099-08-01 10:00:00+00',
    true,
    'UTC'
);

insert into event_attendee (
    event_id,
    user_id
) values
    ('00000000-0000-0000-0000-00000000c0d5', '00000000-0000-0000-0000-00000000c0e8'),
    ('00000000-0000-0000-0000-00000000c0d5', '00000000-0000-0000-0000-00000000c0e9');

-- ============================================================================
-- CFS
-- ============================================================================

insert into session_proposal (
    created_at,
    description,
    duration,
    session_proposal_id,
    session_proposal_level_id,
    title,
    user_id,

    co_speaker_user_id,
    session_proposal_status_id
) values
    (
        '2024-01-02 10:00:00+00',
        'A Rust session proposal used by Rust database contract tests',
        make_interval(mins => 45),
        '00000000-0000-0000-0000-00000000c0c1',
        'beginner',
        'Contract Rust Proposal',
        '00000000-0000-0000-0000-00000000c042',
        null,
        'ready-for-submission'
    ),
    (
        '2024-01-03 10:00:00+00',
        'A Go session proposal used by Rust database contract tests',
        make_interval(mins => 60),
        '00000000-0000-0000-0000-00000000c0c2',
        'intermediate',
        'Contract Go Proposal',
        '00000000-0000-0000-0000-00000000c042',
        '00000000-0000-0000-0000-00000000c043',
        'pending-co-speaker-response'
    );

insert into event_cfs_label (
    color,
    event_cfs_label_id,
    event_id,
    name
) values (
    '#DBEAFE',
    '00000000-0000-0000-0000-00000000c0c8',
    '00000000-0000-0000-0000-00000000c031',
    'track / backend'
);

insert into cfs_submission (
    cfs_submission_id,
    created_at,
    event_id,
    session_proposal_id,
    status_id,

    reviewed_by
) values (
    '00000000-0000-0000-0000-00000000c0c5',
    '2024-01-05 10:00:00+00',
    '00000000-0000-0000-0000-00000000c031',
    '00000000-0000-0000-0000-00000000c0c1',
    'approved',
    '00000000-0000-0000-0000-00000000c041'
);

insert into cfs_submission_label (
    cfs_submission_id,
    event_cfs_label_id
) values (
    '00000000-0000-0000-0000-00000000c0c5',
    '00000000-0000-0000-0000-00000000c0c8'
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

insert into audit_log (
    action,
    actor_user_id,
    actor_username,
    audit_log_id,
    community_id,
    created_at,
    details,
    event_id,
    resource_id,
    resource_type
) values (
    'event_attendee_invitation_rejected',
    '00000000-0000-0000-0000-00000000c042',
    'contract-attendee',
    '00000000-0000-0000-0000-00000000c092',
    '00000000-0000-0000-0000-00000000c001',
    '2024-01-10 10:00:00+00',
    '{"event_name":"Future Contract Event"}'::jsonb,
    '00000000-0000-0000-0000-00000000c031',
    '00000000-0000-0000-0000-00000000c031',
    'event'
);

commit;
