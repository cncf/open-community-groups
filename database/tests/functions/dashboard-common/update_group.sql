-- Tests updating group settings and relationships.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(58);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1c020000-0000-0000-0000-000000000001'
\set eventAutomaticTaxID '1c020000-0000-0000-0000-00000000001c'
\set eventCategoryID '1c020000-0000-0000-0000-000000000002'
\set eventEnableAbroadID '1c020000-0000-0000-0000-00000000003c'
\set eventExternalPaidID '1c020000-0000-0000-0000-000000000038'
\set eventFreeID '1c020000-0000-0000-0000-000000000014'
\set eventID '1c020000-0000-0000-0000-000000000003'
\set eventUnpublishedID '1c020000-0000-0000-0000-000000000004'
\set eventVenueCountryID '1c020000-0000-0000-0000-00000000003b'
\set group2ID '1c020000-0000-0000-0000-000000000005'
\set group3ID '1c020000-0000-0000-0000-000000000006'
\set group4ID '1c020000-0000-0000-0000-000000000007'
\set group5ID '1c020000-0000-0000-0000-000000000008'
\set group6ID '1c020000-0000-0000-0000-000000000015'
\set groupAdminID '1c020000-0000-0000-0000-000000000010'
\set groupAutomaticTaxID '1c020000-0000-0000-0000-00000000001d'
\set groupCategory1ID '1c020000-0000-0000-0000-000000000009'
\set groupCategory2ID '1c020000-0000-0000-0000-00000000000a'
\set groupDeletedID '1c020000-0000-0000-0000-00000000000b'
\set groupDelistedID '1c020000-0000-0000-0000-000000000036'
\set groupDisableID '1c020000-0000-0000-0000-000000000030'
\set groupEnableAbroadID '1c020000-0000-0000-0000-00000000003e'
\set groupEnableID '1c020000-0000-0000-0000-000000000031'
\set groupExternalPaidID '1c020000-0000-0000-0000-000000000037'
\set groupFinalCountryID '1c020000-0000-0000-0000-000000000032'
\set groupID '1c020000-0000-0000-0000-00000000000c'
\set groupMoveCountryDisableID '1c020000-0000-0000-0000-000000000033'
\set groupMoveCountryID '1c020000-0000-0000-0000-000000000034'
\set groupRejectEnableID '1c020000-0000-0000-0000-000000000035'
\set groupVenueCountryID '1c020000-0000-0000-0000-00000000003d'
\set inactiveParentGroupID '1c020000-0000-0000-0000-00000000001a'
\set inactiveParentedGroupID '1c020000-0000-0000-0000-00000000001b'
\set nonExistentCommunityID '1c020000-0000-0000-0000-00000000000d'
\set noPermissionUserID '1c020000-0000-0000-0000-000000000011'
\set parentGroupID '1c020000-0000-0000-0000-000000000012'
\set priceWindowAutomaticTaxID '1c020000-0000-0000-0000-00000000001e'
\set priceWindowEnableAbroadID '1c020000-0000-0000-0000-000000000042'
\set priceWindowExternalPaidID '1c020000-0000-0000-0000-00000000003a'
\set priceWindowFreeID '1c020000-0000-0000-0000-000000000017'
\set priceWindowID '1c020000-0000-0000-0000-000000000016'
\set priceWindowUnpublishedID '1c020000-0000-0000-0000-000000000018'
\set priceWindowVenueCountryID '1c020000-0000-0000-0000-000000000041'
\set ticketTypeAutomaticTaxID '1c020000-0000-0000-0000-00000000001f'
\set ticketTypeEnableAbroadID '1c020000-0000-0000-0000-000000000040'
\set ticketTypeExternalPaidID '1c020000-0000-0000-0000-000000000039'
\set ticketTypeFreeID '1c020000-0000-0000-0000-000000000019'
\set ticketTypeID '1c020000-0000-0000-0000-00000000000e'
\set ticketTypeUnpublishedID '1c020000-0000-0000-0000-00000000000f'
\set ticketTypeVenueCountryID '1c020000-0000-0000-0000-00000000003f'
\set unauthorizedParentGroupID '1c020000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Operator allowlist used by external-payments toggle scenarios
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['JP', 'KR']::text[],
    72,
    336
);

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategory1ID', :'communityID', 'Technology'),
    (:'groupCategory2ID', :'communityID', 'Business');

-- Users
insert into "user" (user_id, auth_hash, email, username) values
    (:'groupAdminID', 'hash-1', 'group-admin@example.com', 'group-admin'),
    (:'noPermissionUserID', 'hash-2', 'no-permission@example.com', 'no-permission');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    created_at
) values (
    :'groupID',
    'Original Group',
    'abc1234',
    :'communityID',
    :'groupCategory1ID',
    'Original description',
    '2024-01-15 10:00:00+00'
);

-- Groups used for parent relationship updates
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    created_at
) values
    (
        :'parentGroupID'::uuid,
        'Parent Group',
        'parent-group',
        :'communityID',
        :'groupCategory1ID',
        'Parent group for hierarchy tests',
        '2024-01-15 10:00:00+00'
    ),
    (
        :'unauthorizedParentGroupID'::uuid,
        'Unauthorized Parent Group',
        'unauthorized-parent-group',
        :'communityID',
        :'groupCategory1ID',
        'Parent group without actor permissions',
        '2024-01-15 10:00:00+00'
    );

-- Inactive parent and its existing child used by the no-op parent scenario
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    slug,

    active,
    description,
    parent_group_id
) values (
    :'communityID',
    :'groupCategory1ID',
    :'inactiveParentGroupID',
    'Inactive Parent Group',
    'inactive-parent-group',

    true,
    'Inactive parent for hierarchy tests',
    null
), (
    :'communityID',
    :'groupCategory1ID',
    :'inactiveParentedGroupID',
    'Inactive Parented Group',
    'inactive-parented-group',

    true,
    'Group with an inactive existing parent',
    :'inactiveParentGroupID'
);

-- Inactivate the established parent without changing the existing relationship
update "group"
set active = false
where group_id = :'inactiveParentGroupID';

-- Parent group team
insert into group_team (group_id, user_id, role, accepted)
values (:'parentGroupID', :'groupAdminID', 'admin', true);

-- Group (deleted)
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    active,
    deleted,
    deleted_at,
    created_at
) values (
    :'groupDeletedID',
    'Deleted Group',
    'xyz9876',
    :'communityID',
    :'groupCategory1ID',
    'Deleted group description',
    false,
    true,
    '2024-02-15 10:00:00+00',
    '2024-01-15 10:00:00+00'
);

-- Group with array fields
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    tags,
    photos_urls,
    created_at
) values (
    :'group3ID'::uuid,
    'Test Group for Null Arrays',
    'mno3ghi',
    :'communityID',
    :'groupCategory1ID',
    'Has array fields',
    array['original', 'tags'],
    array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    '2024-01-15 10:00:00+00'
);

-- Group used to verify empty strings convert to null
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    banner_url,
    city,
    state,
    country_code,
    country_name,
    website_url,
    created_at
) values (
    :'group2ID'::uuid,
    'Test Group for Empty Strings',
    'pqr4jkl',
    :'communityID',
    :'groupCategory1ID',
    'Has some values',
    'https://example.com/banner.jpg',
    'San Francisco',
    'CA',
    'US',
    'United States',
    'https://example.com',
    '2024-01-15 10:00:00+00'
);

-- Group for payment recipient audit coverage
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    created_at
) values (
    :'group4ID'::uuid,
    'Group With Payment Recipient',
    'stu5nop',
    :'communityID',
    :'groupCategory1ID',
    'Payment recipient audit coverage',
    '2024-01-15 10:00:00+00'
);

-- Group with an unpublished ticketed event for payment recipient guards
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    payment_recipient,
    created_at
) values (
    :'group5ID'::uuid,
    'Group With Unpublished Ticketed Event',
    'vwx6qrs',
    :'communityID',
    :'groupCategory1ID',
    'Unpublished ticketed event coverage',
    '{"provider": "stripe", "recipient_id": "acct_456", "seller_display_name": "Existing Fiscal Sponsor"}'::jsonb,
    '2024-01-15 10:00:00+00'
);

-- Published ticketed event used for payment recipient guards
insert into event (
    description,
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    manual_tax_rate_ids,
    name,
    payment_currency_code,
    published,
    slug,
    tax_behavior,
    tax_calculation_mode,
    timezone,
    venue_address,
    venue_city,
    venue_country_code,
    venue_name,
    venue_state_code,
    venue_state_name,
    venue_zip_code
) values (
    'Published ticketed event for payment recipient validation',
    :'eventID'::uuid,
    :'eventCategoryID'::uuid,
    'in-person',
    :'group4ID'::uuid,
    array['txr_update_group']::text[],
    'Ticketed Group Event',
    'USD',
    true,
    'ticketed-group-event',
    'inclusive',
    'manual',
    'UTC',
    '123 Main St',
    'Portland',
    'US',
    'Community Hall',
    'OR',
    'Oregon',
    '97201'
);

-- Group with a published all-zero ticketed event
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    payment_recipient,
    created_at
) values (
    :'group6ID'::uuid,
    'Group With Free Ticketed Event',
    'yz17tuv',
    :'communityID',
    :'groupCategory1ID',
    'Free ticketed event coverage',
    '{"provider": "stripe", "recipient_id": "acct_free", "seller_display_name": "Free Event Fiscal Sponsor"}'::jsonb,
    '2024-01-15 10:00:00+00'
);

-- Group with a published automatic-tax event for validation freshness checks
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,

    description,
    payment_recipient
) values (
    :'groupAutomaticTaxID'::uuid,
    :'communityID'::uuid,
    :'groupCategory1ID'::uuid,
    'Group With Automatic Tax Event',
    'automatic-tax-event-group',

    'Automatic-tax validation freshness coverage',
    '{"provider": "stripe", "recipient_id": "acct_automatic", "seller_display_name": "Existing Fiscal Sponsor"}'::jsonb
);

-- Published all-zero ticketed event used for payment recipient guards
insert into event (
    description,
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    timezone
) values (
    'Published free ticketed event for payment recipient validation',
    :'eventFreeID'::uuid,
    :'eventCategoryID'::uuid,
    'virtual',
    :'group6ID'::uuid,
    'Free Ticketed Group Event',
    true,
    'free-ticketed-group-event',
    'UTC'
);

-- Published automatic-tax event used to reject stale provider validation
insert into event (
    description,
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    tax_calculation_mode,
    timezone
) values (
    'Published automatic-tax event for validation freshness checks',
    :'eventAutomaticTaxID'::uuid,
    :'eventCategoryID'::uuid,
    'virtual',
    :'groupAutomaticTaxID'::uuid,
    'Automatic Tax Event',
    'USD',
    true,
    'automatic-tax-event',
    'automatic',
    'UTC'
);

-- Group whose only paid event is collected outside Stripe
insert into "group" (
    community_id,
    country_code,
    created_at,
    description,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    payment_recipient,
    slug
) values (
    :'communityID'::uuid,
    'KR',
    '2024-01-15 10:00:00+00',
    'External paid event recipient coverage',
    true,
    :'groupCategory1ID'::uuid,
    :'groupExternalPaidID'::uuid,
    'Group With External Paid Event',
    '{"provider": "stripe", "recipient_id": "acct_external", "seller_display_name": "External Event Fiscal Sponsor"}'::jsonb,
    'external-paid-event-group'
);

-- Published external paid event that must not lock the Stripe recipient
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    external_payment_url,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    tax_calculation_mode,
    timezone
) values (
    'Published external paid event for recipient guards',
    :'eventCategoryID'::uuid,
    :'eventExternalPaidID'::uuid,
    'in-person',
    'https://pay.example.test/group',
    :'groupExternalPaidID'::uuid,
    'External Paid Event',
    'KRW',
    true,
    'external-paid-event',
    current_timestamp + interval '7 days',
    'manual',
    'UTC'
);

-- Ticket type for the published automatic-tax event
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeAutomaticTaxID'::uuid,
    :'eventAutomaticTaxID'::uuid,
    1,
    50,
    'Automatic tax admission'
);

-- Ticket type for the published external paid event
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeExternalPaidID'::uuid,
    :'eventExternalPaidID'::uuid,
    1,
    50,
    'External admission'
);

-- Ticket type for the published all-zero ticketed event
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeFreeID'::uuid,
    :'eventFreeID'::uuid,
    1,
    50,
    'Free admission'
);

-- Ticket type for the published ticketed event
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeID'::uuid,
    :'eventID'::uuid,
    1,
    50,
    'General admission'
);

-- Unpublished ticketed event used for payment recipient guards
insert into event (
    description,
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    manual_tax_rate_ids,
    name,
    payment_currency_code,
    published,
    slug,
    tax_calculation_mode,
    timezone
) values (
    'Unpublished ticketed event for payment recipient validation',
    :'eventUnpublishedID'::uuid,
    :'eventCategoryID'::uuid,
    'virtual',
    :'group5ID'::uuid,
    array['txr_draft']::text[],
    'Draft Ticketed Group Event',
    'USD',
    false,
    'draft-ticketed-group-event',
    'manual',
    'UTC'
);

-- Ticket type for the unpublished ticketed event
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeUnpublishedID'::uuid,
    :'eventUnpublishedID'::uuid,
    1,
    50,
    'General admission'
);

-- Ticket prices define the paid capability of each ticketed event.
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'priceWindowAutomaticTaxID', 2500, :'ticketTypeAutomaticTaxID'),
    (:'priceWindowExternalPaidID', 5000, :'ticketTypeExternalPaidID'),
    (:'priceWindowFreeID', 0, :'ticketTypeFreeID'),
    (:'priceWindowID', 2500, :'ticketTypeID'),
    (:'priceWindowUnpublishedID', 2500, :'ticketTypeUnpublishedID');

-- Allowlisted group used to disable external payments as a kill switch
insert into "group" (
    community_id,
    country_code,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    'KR',
    true,
    :'groupCategory1ID',
    :'groupDisableID',
    'External Disable Group',
    'external-disable-group'
);

-- Allowlisted group used by the successful enable scenario
insert into "group" (
    community_id,
    country_code,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    'KR',
    false,
    :'groupCategory1ID',
    :'groupEnableID',
    'External Enable Group',
    'external-enable-group'
);

-- Non-allowlisted group enabled by changing country in the same update
insert into "group" (
    community_id,
    country_code,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    'US',
    false,
    :'groupCategory1ID',
    :'groupFinalCountryID',
    'External Final Country Group',
    'external-final-country-group'
);

-- Allowlisted enabled group that disables while leaving the allowlist
insert into "group" (
    community_id,
    country_code,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    'KR',
    true,
    :'groupCategory1ID',
    :'groupMoveCountryDisableID',
    'External Move Country Disable Group',
    'external-move-country-disable-group'
);

-- Allowlisted enabled group rejected when moving country while staying enabled
insert into "group" (
    community_id,
    country_code,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    'KR',
    true,
    :'groupCategory1ID',
    :'groupMoveCountryID',
    'External Move Country Group',
    'external-move-country-group'
);

-- Non-allowlisted group rejected when enabling external payments
insert into "group" (
    community_id,
    country_code,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    'US',
    false,
    :'groupCategory1ID',
    :'groupRejectEnableID',
    'External Reject Enable Group',
    'external-reject-enable-group'
);

-- Enabled group whose country is no longer allowlisted
insert into "group" (
    community_id,
    country_code,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    'US',
    true,
    :'groupCategory1ID',
    :'groupDelistedID',
    'External Delisted Group',
    'external-delisted-group'
);

-- Allowlisted group blocked from enabling external payments by an event venue abroad
insert into "group" (
    community_id,
    country_code,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    'JP',
    false,
    :'groupCategory1ID',
    :'groupEnableAbroadID',
    'External Enable Abroad Group',
    'external-enable-abroad-group'
);

-- Allowlisted enabled group blocked from moving country by an upcoming external event
insert into "group" (
    community_id,
    country_code,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    'KR',
    true,
    :'groupCategory1ID',
    :'groupVenueCountryID',
    'External Venue Country Group',
    'external-venue-country-group'
);

-- Published external paid event whose venue is outside its disabled group's country
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    external_payment_url,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    tax_calculation_mode,
    timezone,
    venue_address,
    venue_city,
    venue_country_code,
    venue_name,
    venue_zip_code
) values (
    'Published external paid event held outside the group country',
    :'eventCategoryID'::uuid,
    :'eventEnableAbroadID'::uuid,
    'in-person',
    'https://pay.example.test/enable-abroad',
    :'groupEnableAbroadID'::uuid,
    'External Enable Abroad Event',
    'KRW',
    true,
    'external-enable-abroad-event',
    current_timestamp + interval '7 days',
    'none',
    'UTC',
    '1 Test Street',
    'Seoul',
    'KR',
    'Test Hall',
    '00000'
);

-- Published external paid event anchoring its group to the venue country
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    external_payment_url,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    tax_calculation_mode,
    timezone,
    venue_address,
    venue_city,
    venue_country_code,
    venue_name,
    venue_zip_code
) values (
    'Published external paid event held in the group country',
    :'eventCategoryID'::uuid,
    :'eventVenueCountryID'::uuid,
    'in-person',
    'https://pay.example.test/venue-country',
    :'groupVenueCountryID'::uuid,
    'External Venue Country Event',
    'KRW',
    true,
    'external-venue-country-event',
    current_timestamp + interval '7 days',
    'none',
    'UTC',
    '1 Test Street',
    'Seoul',
    'KR',
    'Test Hall',
    '00000'
);

-- Ticket types for the external venue-country events
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values
    (:'ticketTypeEnableAbroadID'::uuid, :'eventEnableAbroadID'::uuid, 1, 50, 'External admission'),
    (:'ticketTypeVenueCountryID'::uuid, :'eventVenueCountryID'::uuid, 1, 50, 'External admission');

-- Ticket prices making the external venue-country events paid
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'priceWindowEnableAbroadID', 5000, :'ticketTypeEnableAbroadID'),
    (:'priceWindowVenueCountryID', 5000, :'ticketTypeVenueCountryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update all provided fields correctly
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Updated Group",
            "category_id": "%s",
            "description": "Updated description",
            "description_short": "Updated brief description",
            "city": "New York",
            "state": "NY",
            "slug_pretty": "updated-group",
            "country_code": "US",
            "country_name": "United States",
            "website_url": "https://updated.example.com",
            "bluesky_url": "https://bsky.app/profile/updated",
            "facebook_url": "https://facebook.com/updated",
            "twitter_url": "https://twitter.com/updated",
            "tags": ["updated", "test"],
            "logo_url": "https://example.com/updated-logo.png",
            "og_image_url": "https://example.com/updated-og.png"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupID',
        :'groupCategory2ID'
    ),
    'Should update all provided fields correctly'
);

-- Should return expected structure after update
select is(
    (select get_group_full(:'communityID'::uuid, :'groupID'::uuid)::jsonb - 'active' - 'created_at' - 'members_count'),
    format(
        $json$
    {
        "name": "Updated Group",
        "slug": "abc1234",
        "slug_pretty": "updated-group",
        "category": {
            "group_category_id": "%s",
            "name": "Business",
            "normalized_name": "business"
        },
        "community": {
            "banner_mobile_url": "https://example.com/banner_mobile.png",
            "banner_url": "https://example.com/banner.png",
            "community_id": "%s",
            "display_name": "Cloud Native Seattle",
            "logo_url": "https://example.com/logo.png",
            "name": "cloud-native-seattle"
        },
        "group_id": "%s",
        "description": "Updated description",
        "description_short": "Updated brief description",
        "city": "New York",
        "state": "NY",
        "country_code": "US",
        "country_name": "United States",
        "website_url": "https://updated.example.com",
        "bluesky_url": "https://bsky.app/profile/updated",
        "facebook_url": "https://facebook.com/updated",
        "twitter_url": "https://twitter.com/updated",
        "tags": ["updated", "test"],
        "logo_url": "https://example.com/updated-logo.png",
        "og_image_url": "https://example.com/updated-og.png",
        "external_payments_enabled": false,
        "organizers": [],
        "sponsors": [],
        "subgroups": []
    }
        $json$,
        :'groupCategory2ID',
        :'communityID',
        :'groupID'
    )::jsonb,
    'Should update all provided fields and return expected structure'
);

-- Should clear pretty slug when provided as an empty string
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Updated Group",
            "category_id": "%s",
            "description": "Updated description",
            "slug_pretty": ""
        }'::jsonb
    )$$,
        :'communityID',
        :'groupID',
        :'groupCategory2ID'
    ),
    'Should clear pretty slug when provided as an empty string'
);

-- Should reject pretty slugs with invalid characters
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Updated Group",
            "category_id": "%s",
            "description": "Updated description",
            "slug_pretty": "Updated Group"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupID',
        :'groupCategory2ID'
    ),
    'P0001',
    'Pretty slug must use lowercase ASCII letters, numbers, and hyphens only',
    'Should reject pretty slugs with invalid characters'
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
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values
            (
                'group_updated',
                null::uuid,
                null::text,
                %L::uuid,
                %L::uuid,
                'group',
                %L::uuid
            ),
            (
                'group_updated',
                null::uuid,
                null::text,
                %L::uuid,
                %L::uuid,
                'group',
                %L::uuid
            )
    $$,
        :'communityID',
        :'groupID',
        :'groupID',
        :'communityID',
        :'groupID',
        :'groupID'
    ),
    'Should create the expected audit rows'
);

-- Should throw error when updating deleted group
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{"name": "Won''t Work", "category_id": "%s", "description": "This should fail"}'::jsonb
    )$$,
        :'communityID',
        :'groupDeletedID',
        :'groupCategory1ID'
    ),
    'group not found or inactive',
    'Should throw error when trying to update deleted group'
);

-- Should convert empty strings to null for nullable fields
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Updated Group Empty Strings",
            "category_id": "%s",
            "description": "",
            "description_short": "",
            "banner_url": "",
            "city": "",
            "state": "",
            "country_code": "",
            "country_name": "",
            "website_url": "",
            "bluesky_url": "",
            "facebook_url": "",
            "twitter_url": "",
            "linkedin_url": "",
            "github_url": "",
            "slack_url": "",
            "youtube_url": "",
            "instagram_url": "",
            "flickr_url": "",
            "wechat_url": "",
            "logo_url": "",
            "region_id": ""
        }'::jsonb
    )$$,
        :'communityID',
        :'group2ID',
        :'groupCategory1ID'
    ),
    'Should convert empty strings to null for nullable fields'
);

-- Should keep minimal fields after empty-string conversion
select is(
    (select get_group_full(:'communityID'::uuid, :'group2ID'::uuid)::jsonb - 'active' - 'group_id' - 'created_at' - 'members_count' - 'category' - 'community' - 'organizers' - 'sponsors' - 'subgroups'),
    '{
        "name": "Updated Group Empty Strings",
        "slug": "pqr4jkl",
        "logo_url": "https://example.com/logo.png",
        "external_payments_enabled": false
    }'::jsonb,
    'Should persist nulls after empty-string conversion'
);

-- Should throw error when community_id mismatches
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{"name": "Won''t Work", "category_id": "%s", "description": "This should fail"}'::jsonb
    )$$,
        :'nonExistentCommunityID',
        :'groupID',
        :'groupCategory1ID'
    ),
    'group not found or inactive',
    'Should throw error when community_id does not match'
);

-- Should handle explicit null values for array fields
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Updated Group Null Arrays",
            "category_id": "%s",
            "description": "Updated description",
            "tags": null,
            "photos_urls": null
        }'::jsonb
    )$$,
        :'communityID',
        :'group3ID',
        :'groupCategory1ID'
    ),
    'Should handle explicit null values for array fields'
);

-- Should persist explicit null arrays in result
select is(
    (select get_group_full(:'communityID'::uuid, :'group3ID'::uuid)::jsonb - 'active' - 'group_id' - 'created_at' - 'members_count' - 'category' - 'community' - 'organizers' - 'sponsors' - 'subgroups'),
    '{
        "name": "Updated Group Null Arrays",
        "slug": "mno3ghi",
        "description": "Updated description",
        "logo_url": "https://example.com/logo.png",
        "external_payments_enabled": false
    }'::jsonb,
    'Should handle explicit null values for array fields (tags, photos_urls)'
);

-- Should create the payment recipient audit row when the recipient changes
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Payment Recipient",
            "category_id": "%s",
            "description": "Payment recipient audit coverage",
            "_payment_validation": {
                "expected_payment_recipient": null,
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_123",
                    "seller_display_name": "New Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": " acct_123 ",
                "seller_display_name": " New Fiscal Sponsor "
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group4ID',
        :'groupCategory1ID'
    ),
    'Should create the payment recipient audit row when the recipient changes'
);

-- Should create both audit rows when the payment recipient changes
select results_eq(
    format(
        $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
        where group_id = %L::uuid
        order by action asc
    $$,
        :'group4ID'
    ),
    format(
        $$
        values
            (
                'group_payment_recipient_updated',
                null::uuid,
                null::text,
                %L::uuid,
                %L::uuid,
                'group',
                %L::uuid
            ),
            (
                'group_updated',
                null::uuid,
                null::text,
                %L::uuid,
                %L::uuid,
                'group',
                %L::uuid
            )
    $$,
        :'communityID',
        :'group4ID',
        :'group4ID',
        :'communityID',
        :'group4ID',
        :'group4ID'
    ),
    'Should create both audit rows when the payment recipient changes'
);

-- Should persist the normalized payment recipient after the update
select is(
    (select get_group_full(:'communityID'::uuid, :'group4ID'::uuid)::jsonb->'payment_recipient'),
    '{
        "provider": "stripe",
        "recipient_id": "acct_123",
        "seller_display_name": "New Fiscal Sponsor"
    }'::jsonb,
    'Should persist the normalized payment recipient after the update'
);

-- Should reject a sponsor swap that invalidates active manual-tax events
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Payment Recipient",
            "category_id": "%s",
            "description": "Payment recipient validation coverage",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_123",
                    "seller_display_name": "New Fiscal Sponsor"
                },
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_replacement",
                    "seller_display_name": "Replacement Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_replacement",
                "seller_display_name": "Replacement Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group4ID',
        :'groupCategory1ID'
    ),
    'fiscal sponsor cannot be replaced while published manual-tax events are upcoming',
    'Should reject a sponsor swap that invalidates active manual-tax events'
);

-- Should reject a sponsor change validated against stale recipient state
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Unpublished Ticketed Event",
            "category_id": "%s",
            "description": "Unpublished ticketed event coverage",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_stale",
                    "seller_display_name": "Stale Fiscal Sponsor"
                },
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_new",
                    "seller_display_name": "New Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_new",
                "seller_display_name": "New Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group5ID',
        :'groupCategory1ID'
    ),
    'payment configuration changed during provider validation',
    'Should reject a sponsor change validated against stale recipient state'
);

-- Should reject validation that missed a published automatic-tax event
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Automatic Tax Event",
            "category_id": "%s",
            "description": "Automatic-tax validation freshness coverage",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_automatic",
                    "seller_display_name": "Existing Fiscal Sponsor"
                },
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_new",
                    "seller_display_name": "New Fiscal Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_new",
                "seller_display_name": "New Fiscal Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupAutomaticTaxID',
        :'groupCategory1ID'
    ),
    'payment configuration changed during provider validation',
    'Should reject validation that missed a published automatic-tax event'
);

-- Should reject a payment recipient without an attendee-visible seller name
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Payment Recipient",
            "category_id": "%s",
            "description": "Payment recipient validation coverage",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_missing_name"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group4ID',
        :'groupCategory1ID'
    ),
    'payment recipient account and seller name must be provided together',
    'Should reject a payment recipient without an attendee-visible seller name'
);

-- Should reject clearing payment recipient when published ticketed events exist
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Payment Recipient",
            "category_id": "%s",
            "description": "Payment recipient audit coverage",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "   "
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group4ID',
        :'groupCategory1ID'
    ),
    'paid-capable events require a payment recipient',
    'Should reject clearing payment recipient when published paid-capable events exist'
);

-- Should keep the stored payment recipient after rejecting the clear
select is(
    (select get_group_full(:'communityID'::uuid, :'group4ID'::uuid)::jsonb->'payment_recipient'),
    '{
        "provider": "stripe",
        "recipient_id": "acct_123",
        "seller_display_name": "New Fiscal Sponsor"
    }'::jsonb,
    'Should keep the stored payment recipient after rejecting the clear'
);

-- Should allow clearing payment recipient for a published all-zero event
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Free Ticketed Event",
            "category_id": "%s",
            "description": "Free ticketed event coverage",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "   "
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group6ID',
        :'groupCategory1ID'
    ),
    'Should allow clearing payment recipient for a published all-zero event'
);

-- Should clear the stored recipient for a published all-zero event
select is(
    (select get_group_full(:'communityID'::uuid, :'group6ID'::uuid)::jsonb->'payment_recipient'),
    null::jsonb,
    'Should clear the stored recipient for a published all-zero event'
);

-- Should normalize whitespace-only payment recipient ids to null
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Updated Group",
            "category_id": "%s",
            "description": "Updated description",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "   "
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupID',
        :'groupCategory1ID'
    ),
    'Should normalize whitespace-only payment recipient ids to null'
);

-- Should not persist a whitespace-only payment recipient id
select is(
    (select get_group_full(:'communityID'::uuid, :'groupID'::uuid)::jsonb->'payment_recipient'),
    null::jsonb,
    'Should not persist a whitespace-only payment recipient id'
);

-- Should allow clearing payment recipient when only unpublished ticketed events exist
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With Unpublished Ticketed Event",
            "category_id": "%s",
            "description": "Unpublished ticketed event coverage",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "   "
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'group5ID',
        :'groupCategory1ID'
    ),
    'Should allow clearing payment recipient when only unpublished ticketed events exist'
);

-- Should clear the stored payment recipient when only unpublished ticketed events exist
select is(
    (select get_group_full(:'communityID'::uuid, :'group5ID'::uuid)::jsonb->'payment_recipient'),
    null::jsonb,
    'Should clear the stored payment recipient when only unpublished ticketed events exist'
);

-- Should clear draft manual-tax selections after the sponsor changes
select is(
    (select manual_tax_rate_ids from event where event_id = :'eventUnpublishedID'::uuid),
    '{}'::text[],
    'Should require draft manual-tax events to reselect rates after a sponsor change'
);

-- Should update parent when the actor can manage the selected parent
select lives_ok(
    format(
        $$select update_group(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Updated Group",
            "category_id": "%s",
            "description": "Updated description",
            "parent_group_id_present": true,
            "parent_group_id": "%s"
        }'::jsonb
    )$$,
        :'groupAdminID',
        :'communityID',
        :'groupID',
        :'groupCategory1ID',
        :'parentGroupID'
    ),
    'Should update parent when the actor can manage the selected parent'
);

select is(
    (select parent_group_id from "group" where group_id = :'groupID'::uuid),
    :'parentGroupID'::uuid,
    'Should persist the selected parent group'
);

-- Should allow unchanged parent values even when the current parent is inactive
select lives_ok(
    format(
        $$select update_group(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Updated Group With Inactive Parent",
            "category_id": "%s",
            "description": "Updated description",
            "parent_group_id_present": true,
            "parent_group_id": "%s"
        }'::jsonb
    )$$,
        :'noPermissionUserID',
        :'communityID',
        :'inactiveParentedGroupID',
        :'groupCategory1ID',
        :'inactiveParentGroupID'
    ),
    'Should allow unchanged parent values even when the current parent is inactive'
);

-- Should preserve the inactive parent on an unchanged update
select is(
    (
        select parent_group_id
        from "group"
        where group_id = :'inactiveParentedGroupID'::uuid
    ),
    :'inactiveParentGroupID'::uuid,
    'Should preserve the inactive parent on an unchanged update'
);

-- Should allow clearing a parent without parent-side permission
select lives_ok(
    format(
        $$select update_group(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Updated Group With Cleared Parent",
            "category_id": "%s",
            "description": "Updated description",
            "parent_group_id_present": true,
            "parent_group_id": ""
        }'::jsonb
    )$$,
        :'noPermissionUserID',
        :'communityID',
        :'groupID',
        :'groupCategory1ID'
    ),
    'Should allow clearing a parent without parent-side permission'
);

select is(
    (select parent_group_id from "group" where group_id = :'groupID'::uuid),
    null::uuid,
    'Should clear the selected parent group'
);

-- Should reject changing to a parent the actor cannot manage
select throws_ok(
    format(
        $$select update_group(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Updated Group Unauthorized Parent",
            "category_id": "%s",
            "description": "Updated description",
            "parent_group_id_present": true,
            "parent_group_id": "%s"
        }'::jsonb
    )$$,
        :'noPermissionUserID',
        :'communityID',
        :'groupID',
        :'groupCategory1ID',
        :'unauthorizedParentGroupID'
    ),
    'you must be able to manage the selected parent group',
    'Should reject changing to a parent the actor cannot manage'
);

-- Should allow disabling external payments as a kill switch
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Disable Group",
            "category_id": "%s",
            "country_code": "KR",
            "external_payments_enabled": false
        }'::jsonb
    )$$,
        :'communityID',
        :'groupDisableID',
        :'groupCategory1ID'
    ),
    'Should allow disabling external payments as a kill switch'
);

-- Should persist the disabled external-payments toggle
select is(
    (
        select external_payments_enabled
        from "group"
        where group_id = :'groupDisableID'::uuid
    ),
    false,
    'Should persist the disabled external-payments toggle'
);

-- Should allow enabling external payments when the final country is allowlisted
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Enable Group",
            "category_id": "%s",
            "country_code": "KR",
            "external_payments_enabled": true
        }'::jsonb
    )$$,
        :'communityID',
        :'groupEnableID',
        :'groupCategory1ID'
    ),
    'Should allow enabling external payments when the final country is allowlisted'
);

-- Should persist the enabled external-payments toggle for an allowlisted country
select is(
    (
        select external_payments_enabled
        from "group"
        where group_id = :'groupEnableID'::uuid
    ),
    true,
    'Should persist the enabled external-payments toggle for an allowlisted country'
);

-- Should create the external-payments audit row when the toggle changes
select ok(
    exists(
        select 1
        from audit_log
        where action = 'group_external_payments_updated'
        and group_id = :'groupEnableID'::uuid
        and details = '{"external_payments_enabled": true}'::jsonb
    ),
    'Should create the external-payments audit row when the toggle changes'
);

-- Should enable external payments when the same update moves onto the allowlist
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Final Country Group",
            "category_id": "%s",
            "country_code": "KR",
            "country_name": "Korea",
            "external_payments_enabled": true
        }'::jsonb
    )$$,
        :'communityID',
        :'groupFinalCountryID',
        :'groupCategory1ID'
    ),
    'Should enable external payments when the same update moves onto the allowlist'
);

-- Should persist the allowlisted country and enabled toggle together
select is(
    (
        select jsonb_build_object(
            'country_code', country_code,
            'external_payments_enabled', external_payments_enabled
        )
        from "group"
        where group_id = :'groupFinalCountryID'::uuid
    ),
    '{"country_code": "KR", "external_payments_enabled": true}'::jsonb,
    'Should persist the allowlisted country and enabled toggle together'
);

-- Should allow leaving the allowlist when the same update disables external payments
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Move Country Disable Group",
            "category_id": "%s",
            "country_code": "US",
            "country_name": "United States",
            "external_payments_enabled": false
        }'::jsonb
    )$$,
        :'communityID',
        :'groupMoveCountryDisableID',
        :'groupCategory1ID'
    ),
    'Should allow leaving the allowlist when the same update disables external payments'
);

-- Should reject changing country off the allowlist while external payments stay enabled
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Move Country Group",
            "category_id": "%s",
            "country_code": "US",
            "country_name": "United States"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupMoveCountryID',
        :'groupCategory1ID'
    ),
    'external payments are not available for this group country',
    'Should reject changing country off the allowlist while external payments stay enabled'
);

-- Should keep the allowlisted country after rejecting the country move
select is(
    (
        select jsonb_build_object(
            'country_code', country_code,
            'external_payments_enabled', external_payments_enabled
        )
        from "group"
        where group_id = :'groupMoveCountryID'::uuid
    ),
    '{"country_code": "KR", "external_payments_enabled": true}'::jsonb,
    'Should keep the allowlisted country after rejecting the country move'
);

-- Should accept a partial payload that omits country_code while the toggle stays on
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Move Country Group",
            "category_id": "%s"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupMoveCountryID',
        :'groupCategory1ID'
    ),
    'Should accept a partial payload that omits country_code while the toggle stays on'
);

-- Should preserve country when a partial payload omits country_code while the toggle stays on
select is(
    (
        select jsonb_build_object(
            'country_code', country_code,
            'external_payments_enabled', external_payments_enabled
        )
        from "group"
        where group_id = :'groupMoveCountryID'::uuid
    ),
    '{"country_code": "KR", "external_payments_enabled": true}'::jsonb,
    'Should preserve country when a partial payload omits country_code while the toggle stays on'
);

-- Should reject enabling external payments when the country is not allowlisted
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Reject Enable Group",
            "category_id": "%s",
            "country_code": "US",
            "external_payments_enabled": true
        }'::jsonb
    )$$,
        :'communityID',
        :'groupRejectEnableID',
        :'groupCategory1ID'
    ),
    'external payments are not available for this group country',
    'Should reject enabling external payments when the country is not allowlisted'
);

-- Should reject enabling external payments while published external events are held abroad
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Enable Abroad Group",
            "category_id": "%s",
            "country_code": "JP",
            "external_payments_enabled": true
        }'::jsonb
    )$$,
        :'communityID',
        :'groupEnableAbroadID',
        :'groupCategory1ID'
    ),
    'published external paid events require a venue in the group country',
    'Should reject enabling external payments while published external events are held abroad'
);

-- Should reject moving the group country away from upcoming external event venues
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Venue Country Group",
            "category_id": "%s",
            "country_code": "JP",
            "country_name": "Japan"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupVenueCountryID',
        :'groupCategory1ID'
    ),
    'published external paid events require a venue in the group country',
    'Should reject moving the group country away from upcoming external event venues'
);

-- Should keep the group country after rejecting the move away from event venues
select is(
    (
        select jsonb_build_object(
            'country_code', country_code,
            'external_payments_enabled', external_payments_enabled
        )
        from "group"
        where group_id = :'groupVenueCountryID'::uuid
    ),
    '{"country_code": "KR", "external_payments_enabled": true}'::jsonb,
    'Should keep the group country after rejecting the move away from event venues'
);

-- Should allow moving the group country away from event venues when the same update disables external payments
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Venue Country Group",
            "category_id": "%s",
            "country_code": "JP",
            "country_name": "Japan",
            "external_payments_enabled": false
        }'::jsonb
    )$$,
        :'communityID',
        :'groupVenueCountryID',
        :'groupCategory1ID'
    ),
    'Should allow moving the group country away from event venues when the same update disables external payments'
);

-- Should persist the moved country and disabled toggle together
select is(
    (
        select jsonb_build_object(
            'country_code', country_code,
            'external_payments_enabled', external_payments_enabled
        )
        from "group"
        where group_id = :'groupVenueCountryID'::uuid
    ),
    '{"country_code": "JP", "external_payments_enabled": false}'::jsonb,
    'Should persist the moved country and disabled toggle together'
);

-- Should allow unrelated group updates after the country leaves the allowlist
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Delisted Group Updated",
            "category_id": "%s",
            "country_code": "US",
            "country_name": "United States"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupDelistedID',
        :'groupCategory1ID'
    ),
    'Should allow unrelated group updates after the country leaves the allowlist'
);

-- Should keep the toggle enabled after an unrelated save on a delisted country
select is(
    (
        select jsonb_build_object(
            'external_payments_enabled', external_payments_enabled,
            'name', name
        )
        from "group"
        where group_id = :'groupDelistedID'::uuid
    ),
    '{"external_payments_enabled": true, "name": "External Delisted Group Updated"}'::jsonb,
    'Should keep the toggle enabled after an unrelated save on a delisted country'
);

-- Should replace the fiscal sponsor when only external paid events are published
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With External Paid Event",
            "category_id": "%s",
            "description": "External paid event recipient coverage",
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_external",
                    "seller_display_name": "External Event Fiscal Sponsor"
                },
                "require_automatic_tax": false,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_external_replacement",
                    "seller_display_name": "Replacement External Sponsor"
                }
            },
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "acct_external_replacement",
                "seller_display_name": "Replacement External Sponsor"
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupExternalPaidID',
        :'groupCategory1ID'
    ),
    'Should replace the fiscal sponsor when only external paid events are published'
);

-- Should persist the replaced fiscal sponsor for an external-only group
select is(
    (select get_group_full(:'communityID'::uuid, :'groupExternalPaidID'::uuid)::jsonb->'payment_recipient'),
    '{
        "provider": "stripe",
        "recipient_id": "acct_external_replacement",
        "seller_display_name": "Replacement External Sponsor"
    }'::jsonb,
    'Should persist the replaced fiscal sponsor for an external-only group'
);

-- Should clear the fiscal sponsor when only external paid events are published
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Group With External Paid Event",
            "category_id": "%s",
            "description": "External paid event recipient coverage",
            "payment_recipient": {
                "provider": "stripe",
                "recipient_id": "   "
            }
        }'::jsonb
    )$$,
        :'communityID',
        :'groupExternalPaidID',
        :'groupCategory1ID'
    ),
    'Should clear the fiscal sponsor when only external paid events are published'
);

-- Should persist a cleared recipient for an external-only group
select is(
    (select get_group_full(:'communityID'::uuid, :'groupExternalPaidID'::uuid)::jsonb->'payment_recipient'),
    null::jsonb,
    'Should persist a cleared recipient for an external-only group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
