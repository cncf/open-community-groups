-- Tests updating group settings and relationships.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(60);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1c020000-0000-0000-0000-000000000001'
\set eventAutomaticTaxID '1c020000-0000-0000-0000-00000000001c'
\set eventCategoryID '1c020000-0000-0000-0000-000000000002'
\set eventDelistedID '1c020000-0000-0000-0000-000000000043'
\set eventDisablePastID '1c020000-0000-0000-0000-000000000044'
\set eventDisableUnpublishedID '1c020000-0000-0000-0000-000000000045'
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
\set priceWindowDelistedID '1c020000-0000-0000-0000-000000000046'
\set priceWindowDisablePastID '1c020000-0000-0000-0000-000000000047'
\set priceWindowDisableUnpublishedID '1c020000-0000-0000-0000-000000000048'
\set priceWindowEnableAbroadID '1c020000-0000-0000-0000-000000000042'
\set priceWindowExternalPaidID '1c020000-0000-0000-0000-00000000003a'
\set priceWindowFreeID '1c020000-0000-0000-0000-000000000017'
\set priceWindowID '1c020000-0000-0000-0000-000000000016'
\set priceWindowUnpublishedID '1c020000-0000-0000-0000-000000000018'
\set priceWindowVenueCountryID '1c020000-0000-0000-0000-000000000041'
\set ticketTypeAutomaticTaxID '1c020000-0000-0000-0000-00000000001f'
\set ticketTypeDelistedID '1c020000-0000-0000-0000-000000000049'
\set ticketTypeDisablePastID '1c020000-0000-0000-0000-00000000004a'
\set ticketTypeDisableUnpublishedID '1c020000-0000-0000-0000-00000000004b'
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
select fx_community(:'communityID', jsonb_build_object(
    'banner_mobile_url', 'https://example.com/banner_mobile.png',
    'banner_url', 'https://example.com/banner.png',
    'display_name', 'Cloud Native Seattle Update Group',
    'logo_url', 'https://example.com/logo.png',
    'name', 'cloud-native-seattle-update-group'
));

-- Baseline categories, users and groups
select fx_group_category(:'groupCategory1ID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'groupAdminID');
select fx_user(:'noPermissionUserID');
select fx_group(:'inactiveParentGroupID', :'communityID', :'groupCategory1ID');

-- group category
select fx_group_category(:'groupCategory2ID', :'communityID', jsonb_build_object('name', 'Business'));

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'created_at', '2024-01-15 10:00:00+00',
    'slug', 'abc1234'
));

-- Groups used for parent relationship updates
select fx_group(:'parentGroupID'::uuid, :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-15 10:00:00+00'));
-- group
select fx_group(:'unauthorizedParentGroupID'::uuid, :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-15 10:00:00+00'));
-- group
select fx_group(:'inactiveParentedGroupID', :'communityID', :'groupCategory1ID', jsonb_build_object('parent_group_id', :'inactiveParentGroupID'));

-- Inactivate the established parent without changing the existing relationship
update "group"
set active = false
where group_id = :'inactiveParentGroupID';

-- Parent group team
insert into group_team (group_id, user_id, role, accepted)
values (:'parentGroupID', :'groupAdminID', 'admin', true);

-- Group with array fields
select fx_group(:'group3ID'::uuid, :'communityID', :'groupCategory1ID', jsonb_build_object(
    'created_at', '2024-01-15 10:00:00+00',
    'photos_urls', array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    'slug', 'mno3ghi',
    'tags', array['original', 'tags']
));

-- Group used to verify empty strings convert to null
select fx_group(:'group2ID'::uuid, :'communityID', :'groupCategory1ID', jsonb_build_object(
    'city', 'San Francisco',
    'country_code', 'US',
    'country_name', 'United States',
    'created_at', '2024-01-15 10:00:00+00',
    'slug', 'pqr4jkl',
    'state', 'CA',
    'website_url', 'https://example.com'
));

-- Group for payment recipient audit coverage
select fx_group(:'group4ID'::uuid, :'communityID', :'groupCategory1ID', jsonb_build_object(
    'created_at', '2024-01-15 10:00:00+00',
    'description', 'Payment recipient audit coverage',
    'name', 'Group With Payment Recipient'
));

-- Group with an unpublished ticketed event for payment recipient guards
select fx_group(:'group5ID'::uuid, :'communityID', :'groupCategory1ID', jsonb_build_object(
    'created_at', '2024-01-15 10:00:00+00',
    'description', 'Unpublished ticketed event coverage',
    'name', 'Group With Unpublished Ticketed Event',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_456", "seller_display_name": "Existing Fiscal Sponsor"}'::jsonb
));

-- Published ticketed event used for payment recipient guards
select fx_event(:'eventID'::uuid, :'group4ID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'manual_tax_rate_ids', array['txr_update_group']::text[],
    'payment_currency_code', 'USD',
    'published', true,
    'tax_calculation_mode', 'manual',
    'venue_address', '123 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Community Hall',
    'venue_state_code', 'OR',
    'venue_state_name', 'Oregon',
    'venue_zip_code', '97201'
));

-- Group with a published all-zero ticketed event
select fx_group(:'group6ID'::uuid, :'communityID', :'groupCategory1ID', jsonb_build_object(
    'created_at', '2024-01-15 10:00:00+00',
    'description', 'Free ticketed event coverage',
    'name', 'Group With Free Ticketed Event',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_free", "seller_display_name": "Free Event Fiscal Sponsor"}'::jsonb
));

-- Group with a published automatic-tax event for validation freshness checks
select fx_group(:'groupAutomaticTaxID'::uuid, :'communityID'::uuid, :'groupCategory1ID'::uuid, jsonb_build_object(
    'description', 'Automatic-tax validation freshness coverage',
    'name', 'Group With Automatic Tax Event',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_automatic", "seller_display_name": "Existing Fiscal Sponsor"}'::jsonb
));

-- Published all-zero ticketed event used for payment recipient guards
select fx_event(:'eventFreeID'::uuid, :'group6ID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true
));

-- Published automatic-tax event used to reject stale provider validation
select fx_event(:'eventAutomaticTaxID'::uuid, :'groupAutomaticTaxID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'event_kind_id', 'virtual',
    'name', 'Automatic Tax Event',
    'payment_currency_code', 'USD',
    'published', true
));

-- Group whose only paid event is collected outside Stripe
select fx_group(:'groupExternalPaidID'::uuid, :'communityID'::uuid, :'groupCategory1ID'::uuid, jsonb_build_object(
    'country_code', 'KR',
    'created_at', '2024-01-15 10:00:00+00',
    'description', 'External paid event recipient coverage',
    'external_payments_enabled', true,
    'name', 'Group With External Paid Event',
    'payment_recipient', '{"provider": "stripe", "recipient_id": "acct_external", "seller_display_name": "External Event Fiscal Sponsor"}'::jsonb
));

-- Published external paid event that must not lock the Stripe recipient
select fx_event(:'eventExternalPaidID'::uuid, :'groupExternalPaidID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/group',
    'name', 'External Paid Event',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '7 days',
    'tax_calculation_mode', 'manual'
));

-- Ticket type for the published automatic-tax event
select fx_event_ticket_type(:'ticketTypeAutomaticTaxID'::uuid, :'eventAutomaticTaxID'::uuid, jsonb_build_object('seats_total', 50));

-- Ticket type for the published external paid event
select fx_event_ticket_type(:'ticketTypeExternalPaidID'::uuid, :'eventExternalPaidID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));

-- Ticket type for the published all-zero ticketed event
select fx_event_ticket_type(:'ticketTypeFreeID'::uuid, :'eventFreeID'::uuid, jsonb_build_object('seats_total', 50));

-- Ticket type for the published ticketed event
select fx_event_ticket_type(:'ticketTypeID'::uuid, :'eventID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'General admission'
));

-- Unpublished ticketed event used for payment recipient guards
select fx_event(:'eventUnpublishedID'::uuid, :'group5ID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'event_kind_id', 'virtual',
    'manual_tax_rate_ids', array['txr_draft']::text[],
    'payment_currency_code', 'USD',
    'tax_calculation_mode', 'manual'
));

-- Ticket type for the unpublished ticketed event
select fx_event_ticket_type(:'ticketTypeUnpublishedID'::uuid, :'eventUnpublishedID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'General admission'
));

-- Ticket prices define the paid capability of each ticketed event
select fx_event_ticket_price_window(:'priceWindowAutomaticTaxID', :'ticketTypeAutomaticTaxID', jsonb_build_object('amount_minor', 2500));
-- event ticket price window
select fx_event_ticket_price_window(:'priceWindowExternalPaidID', :'ticketTypeExternalPaidID', jsonb_build_object('amount_minor', 5000));
-- event ticket price window
select fx_event_ticket_price_window(:'priceWindowFreeID', :'ticketTypeFreeID', jsonb_build_object('amount_minor', 0));
-- event ticket price window
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 2500));
-- event ticket price window
select fx_event_ticket_price_window(:'priceWindowUnpublishedID', :'ticketTypeUnpublishedID', jsonb_build_object('amount_minor', 2500));

-- Allowlisted group disabling external payments with only past or unpublished external events
select fx_group(:'groupDisableID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'name', 'External Disable Group'
));

-- Allowlisted group used by the successful enable scenario
select fx_group(:'groupEnableID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'country_code', 'KR',
    'name', 'External Enable Group'
));

-- Non-allowlisted group enabled by changing country in the same update
select fx_group(:'groupFinalCountryID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'country_code', 'US',
    'name', 'External Final Country Group'
));

-- Allowlisted enabled group that disables while leaving the allowlist
select fx_group(:'groupMoveCountryDisableID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'name', 'External Move Country Disable Group'
));

-- Allowlisted enabled group rejected when moving country while staying enabled
select fx_group(:'groupMoveCountryID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'name', 'External Move Country Group'
));

-- Non-allowlisted group rejected when enabling external payments
select fx_group(:'groupRejectEnableID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'country_code', 'US',
    'name', 'External Reject Enable Group'
));

-- Enabled group whose country is no longer allowlisted despite an upcoming external event
select fx_group(:'groupDelistedID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'country_code', 'US',
    'external_payments_enabled', true,
    'name', 'External Delisted Group'
));

-- Allowlisted group blocked from enabling external payments by an event venue abroad
select fx_group(:'groupEnableAbroadID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'country_code', 'JP',
    'name', 'External Enable Abroad Group'
));

-- Allowlisted enabled group blocked from moving country by an upcoming external event
select fx_group(:'groupVenueCountryID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'name', 'External Venue Country Group'
));

-- Published external paid event whose venue is outside its disabled group's country
select fx_event(:'eventEnableAbroadID'::uuid, :'groupEnableAbroadID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/enable-abroad',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '7 days',
    'tax_calculation_mode', 'none',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Published external paid event anchoring its group to the venue country
select fx_event(:'eventVenueCountryID'::uuid, :'groupVenueCountryID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/venue-country',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '7 days',
    'tax_calculation_mode', 'none',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Ticket types for the external venue-country events
select fx_event_ticket_type(:'ticketTypeEnableAbroadID'::uuid, :'eventEnableAbroadID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));
-- event ticket type
select fx_event_ticket_type(:'ticketTypeVenueCountryID'::uuid, :'eventVenueCountryID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));

-- Ticket prices making the external venue-country events paid
select fx_event_ticket_price_window(:'priceWindowEnableAbroadID', :'ticketTypeEnableAbroadID', jsonb_build_object('amount_minor', 5000));
-- event ticket price window
select fx_event_ticket_price_window(:'priceWindowVenueCountryID', :'ticketTypeVenueCountryID', jsonb_build_object('amount_minor', 5000));

-- Upcoming published external paid event in the delisted group
select fx_event(:'eventDelistedID'::uuid, :'groupDelistedID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/delisted',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '7 days',
    'tax_calculation_mode', 'none',
    'venue_address', '1 Test Street',
    'venue_city', 'Austin',
    'venue_country_code', 'US',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Past published external paid event that must not block disabling the toggle
select fx_event(:'eventDisablePastID'::uuid, :'groupDisableID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'ends_at', current_timestamp - interval '6 days',
    'external_payment_url', 'https://pay.example.test/disable-past',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp - interval '7 days',
    'tax_calculation_mode', 'none',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Unpublished upcoming external paid event that must not block disabling the toggle
select fx_event(:'eventDisableUnpublishedID'::uuid, :'groupDisableID'::uuid, :'eventCategoryID'::uuid, jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/disable-draft',
    'payment_currency_code', 'KRW',
    'starts_at', current_timestamp + interval '7 days',
    'tax_calculation_mode', 'none',
    'venue_address', '1 Test Street',
    'venue_city', 'Seoul',
    'venue_country_code', 'KR',
    'venue_name', 'Test Hall',
    'venue_zip_code', '00000'
));

-- Ticket types for the toggle-disable external events
select fx_event_ticket_type(:'ticketTypeDelistedID'::uuid, :'eventDelistedID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));
-- event ticket type
select fx_event_ticket_type(:'ticketTypeDisablePastID'::uuid, :'eventDisablePastID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));
-- event ticket type
select fx_event_ticket_type(:'ticketTypeDisableUnpublishedID'::uuid, :'eventDisableUnpublishedID'::uuid, jsonb_build_object(
    'seats_total', 50,
    'title', 'External admission'
));

-- Ticket prices making the toggle-disable external events paid
select fx_event_ticket_price_window(:'priceWindowDelistedID', :'ticketTypeDelistedID', jsonb_build_object('amount_minor', 5000));
-- event ticket price window
select fx_event_ticket_price_window(:'priceWindowDisablePastID', :'ticketTypeDisablePastID', jsonb_build_object('amount_minor', 5000));
-- event ticket price window
select fx_event_ticket_price_window(:'priceWindowDisableUnpublishedID', :'ticketTypeDisableUnpublishedID', jsonb_build_object('amount_minor', 5000));

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
            "display_name": "Cloud Native Seattle Update Group",
            "logo_url": "https://example.com/logo.png",
            "name": "cloud-native-seattle-update-group"
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
    'you must be able to manage the selected parent group',
    'Should reject changing to a parent the actor cannot manage'
);

-- Should allow disabling external payments when no upcoming published external events remain
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
    'Should allow disabling external payments when no upcoming published external events remain'
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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

-- Should reject disabling external payments while published external paid events are upcoming
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "External Venue Country Group",
            "category_id": "%s",
            "country_code": "KR",
            "external_payments_enabled": false
        }'::jsonb
    )$$,
        :'communityID',
        :'groupVenueCountryID',
        :'groupCategory1ID'
    ),
    'OCG01',
    'external payments cannot be disabled while published external paid events are upcoming',
    'Should reject disabling external payments while published external paid events are upcoming'
);

-- Should reject moving the group country away from event venues when the same update disables external payments
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
            "country_name": "Japan",
            "external_payments_enabled": false
        }'::jsonb
    )$$,
        :'communityID',
        :'groupVenueCountryID',
        :'groupCategory1ID'
    ),
    'OCG01',
    'external payments cannot be disabled while published external paid events are upcoming',
    'Should reject moving the group country away from event venues when the same update disables external payments'
);

-- Should keep the country and enabled toggle after rejecting the disable
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
    'Should keep the country and enabled toggle after rejecting the disable'
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

-- Should allow disabling external payments on a delisted country despite upcoming external events
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
            "country_name": "United States",
            "external_payments_enabled": false
        }'::jsonb
    )$$,
        :'communityID',
        :'groupDelistedID',
        :'groupCategory1ID'
    ),
    'Should allow disabling external payments on a delisted country despite upcoming external events'
);

-- Should persist the disabled toggle for the delisted country
select is(
    (
        select external_payments_enabled
        from "group"
        where group_id = :'groupDelistedID'::uuid
    ),
    false,
    'Should persist the disabled toggle for the delisted country'
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
