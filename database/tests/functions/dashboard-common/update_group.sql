-- Tests updating group settings and relationships.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(33);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1c020000-0000-0000-0000-000000000001'
\set eventCategoryID '1c020000-0000-0000-0000-000000000002'
\set eventFreeID '1c020000-0000-0000-0000-000000000014'
\set eventID '1c020000-0000-0000-0000-000000000003'
\set eventUnpublishedID '1c020000-0000-0000-0000-000000000004'
\set group2ID '1c020000-0000-0000-0000-000000000005'
\set group3ID '1c020000-0000-0000-0000-000000000006'
\set group4ID '1c020000-0000-0000-0000-000000000007'
\set group5ID '1c020000-0000-0000-0000-000000000008'
\set group6ID '1c020000-0000-0000-0000-000000000015'
\set groupAdminID '1c020000-0000-0000-0000-000000000010'
\set groupCategory1ID '1c020000-0000-0000-0000-000000000009'
\set groupCategory2ID '1c020000-0000-0000-0000-00000000000a'
\set groupDeletedID '1c020000-0000-0000-0000-00000000000b'
\set groupID '1c020000-0000-0000-0000-00000000000c'
\set inactiveParentGroupID '1c020000-0000-0000-0000-00000000001a'
\set inactiveParentedGroupID '1c020000-0000-0000-0000-00000000001b'
\set manualTaxConfigurationID '1c020000-0000-0000-0000-00000000001c'
\set nonExistentCommunityID '1c020000-0000-0000-0000-00000000000d'
\set noPermissionUserID '1c020000-0000-0000-0000-000000000011'
\set parentGroupID '1c020000-0000-0000-0000-000000000012'
\set priceWindowFreeID '1c020000-0000-0000-0000-000000000017'
\set priceWindowID '1c020000-0000-0000-0000-000000000016'
\set priceWindowUnpublishedID '1c020000-0000-0000-0000-000000000018'
\set ticketTypeFreeID '1c020000-0000-0000-0000-000000000019'
\set ticketTypeID '1c020000-0000-0000-0000-00000000000e'
\set ticketTypeUnpublishedID '1c020000-0000-0000-0000-00000000000f'
\set unauthorizedParentGroupID '1c020000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

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

-- Manual-tax approval that is valid only for the initial sponsor
insert into event_manual_tax_configuration (
    approved_at,
    approved_by_user_id,
    connected_seller_id,
    currency_code,
    event_id,
    event_manual_tax_configuration_id,
    evidence_reference,
    tax_behavior,
    venue_snapshot,
    version
) values (
    current_timestamp,
    :'groupAdminID',
    'acct_123',
    'USD',
    :'eventID',
    :'manualTaxConfigurationID',
    'approval-update-group-test',
    'inclusive',
    '{
        "address": "123 Main St",
        "city": "Portland",
        "country_code": "US",
        "name": "Community Hall",
        "state_code": "OR",
        "state_name": "Oregon",
        "zip_code": "97201"
    }'::jsonb,
    1
);

insert into event_manual_tax_component (
    display_name,
    event_manual_tax_configuration_id,
    jurisdiction,
    percentage,
    provider_tax_rate_id,
    tax_behavior,
    tax_type
) values (
    'Oregon admissions tax',
    :'manualTaxConfigurationID',
    'Oregon',
    1.0000,
    'txr_update_group',
    'inclusive',
    'sales_tax'
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

-- Unpublished ticketed event used for payment recipient guards
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
    timezone
) values (
    'Unpublished ticketed event for payment recipient validation',
    :'eventUnpublishedID'::uuid,
    :'eventCategoryID'::uuid,
    'virtual',
    :'group5ID'::uuid,
    'Draft Ticketed Group Event',
    'USD',
    false,
    'draft-ticketed-group-event',
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
    (:'priceWindowID', 2500, :'ticketTypeID'),
    (:'priceWindowFreeID', 0, :'ticketTypeFreeID'),
    (:'priceWindowUnpublishedID', 2500, :'ticketTypeUnpublishedID');

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
        "logo_url": "https://example.com/logo.png"
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
        "logo_url": "https://example.com/logo.png"
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
    'manual ticket tax is not ready for this sponsor and venue',
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

-- Should reject validation that missed a concurrently published automatic-tax event
update event set published = true where event_id = :'eventUnpublishedID';
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
                    "recipient_id": "acct_456",
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
        :'group5ID',
        :'groupCategory1ID'
    ),
    'payment configuration changed during provider validation',
    'Should reject validation that missed a concurrently published automatic-tax event'
);
update event set published = false where event_id = :'eventUnpublishedID';

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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
