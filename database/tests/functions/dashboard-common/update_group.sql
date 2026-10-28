-- Tests updating group settings and relationships.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(26);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '1c020000-0000-0000-0000-000000000001'
\set group2ID '1c020000-0000-0000-0000-000000000005'
\set group3ID '1c020000-0000-0000-0000-000000000006'
\set groupAdminID '1c020000-0000-0000-0000-000000000010'
\set groupCategory1ID '1c020000-0000-0000-0000-000000000009'
\set groupCategory2ID '1c020000-0000-0000-0000-00000000000a'
\set groupClearParentID '1c020000-0000-0000-0000-000000000060'
\set groupID '1c020000-0000-0000-0000-00000000000c'
\set groupParentUpdateID '1c020000-0000-0000-0000-000000000014'
\set groupSlugClearID '1c020000-0000-0000-0000-000000000068'
\set groupUtmApplyID '1c020000-0000-0000-0000-00000000005c'
\set groupUtmClearID '1c020000-0000-0000-0000-00000000005d'
\set groupUtmDefaultMediumID '1c020000-0000-0000-0000-00000000005e'
\set groupUtmPreserveID '1c020000-0000-0000-0000-00000000005f'
\set inactiveParentGroupID '1c020000-0000-0000-0000-00000000001a'
\set inactiveParentedGroupID '1c020000-0000-0000-0000-00000000001b'
\set nonExistentCommunityID '1c020000-0000-0000-0000-00000000000d'
\set noPermissionUserID '1c020000-0000-0000-0000-000000000011'
\set parentGroupID '1c020000-0000-0000-0000-000000000012'
\set unauthorizedParentGroupID '1c020000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

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
select fx_user(:'groupAdminID', jsonb_build_object('username', 'update-group-audit-actor'));
select fx_user(:'noPermissionUserID');
select fx_group(:'inactiveParentGroupID', :'communityID', :'groupCategory1ID');

-- Category assigned by the update scenarios
select fx_group_category(:'groupCategory2ID', :'communityID', jsonb_build_object('name', 'Business'));

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'created_at', '2024-01-15 10:00:00+00',
    'slug', 'abc1234'
));

-- Parent group the actor manages
select fx_group(:'parentGroupID'::uuid, :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-15 10:00:00+00'));

-- Group whose stored parent is cleared without parent-side permission
select fx_group(:'groupClearParentID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'name', 'Clear Parent Group',
    'parent_group_id', :'parentGroupID'
));

-- Group whose parent is set by an actor that manages it
select fx_group(:'groupParentUpdateID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'name', 'Parent Update Group'
));

-- Group whose stored pretty slug is cleared
select fx_group(:'groupSlugClearID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'name', 'Slug Clear Group',
    'slug_pretty', 'update-group-slug-clear'
));

-- Parent group the actor cannot manage
select fx_group(:'unauthorizedParentGroupID'::uuid, :'communityID', :'groupCategory1ID', jsonb_build_object('created_at', '2024-01-15 10:00:00+00'));

-- Group already linked to the parent that becomes inactive
select fx_group(:'inactiveParentedGroupID', :'communityID', :'groupCategory1ID', jsonb_build_object('parent_group_id', :'inactiveParentGroupID'));

-- The parent trigger rejects inactive parents on insert, so inactivate the
-- established parent after linking it
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

-- Group whose UTM values are replaced
select fx_group(:'groupUtmApplyID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'name', 'UTM Apply Group',
    'utm_campaigns', jsonb_build_array('old-campaign'),
    'utm_mediums', jsonb_build_array('podcast'),
    'utm_sources', jsonb_build_array('old-source')
));

-- Group whose UTM values are cleared
select fx_group(:'groupUtmClearID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'name', 'UTM Clear Group',
    'utm_campaigns', jsonb_build_array('old-campaign'),
    'utm_mediums', jsonb_build_array('podcast'),
    'utm_sources', jsonb_build_array('old-source')
));

-- Group rejecting extra mediums that are accepted by default
select fx_group(:'groupUtmDefaultMediumID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'name', 'UTM Default Medium Group',
    'utm_campaigns', jsonb_build_array('old-campaign'),
    'utm_mediums', jsonb_build_array('podcast'),
    'utm_sources', jsonb_build_array('old-source')
));

-- Group keeping its UTM values on a partial payload
select fx_group(:'groupUtmPreserveID', :'communityID', :'groupCategory1ID', jsonb_build_object(
    'name', 'UTM Preserve Group',
    'utm_campaigns', jsonb_build_array('old-campaign'),
    'utm_mediums', jsonb_build_array('podcast'),
    'utm_sources', jsonb_build_array('old-source')
));

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
        "custom_logo_url": "https://example.com/updated-logo.png",
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
            "name": "Slug Clear Group",
            "category_id": "%s",
            "slug_pretty": ""
        }'::jsonb
    )$$,
        :'communityID',
        :'groupSlugClearID',
        :'groupCategory1ID'
    ),
    'Should clear pretty slug when provided as an empty string'
);

-- Should store a null pretty slug after clearing it
select is(
    (select slug_pretty from "group" where group_id = :'groupSlugClearID'::uuid),
    null::text,
    'Should store a null pretty slug after clearing it'
);

-- Should create the expected audit rows
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
        order by resource_id
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
        :'groupSlugClearID',
        :'groupSlugClearID'
    ),
    'Should create the expected audit rows'
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

-- Should update parent when the actor can manage the selected parent
select lives_ok(
    format(
        $$select update_group(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "Parent Update Group",
            "category_id": "%s",
            "parent_group_id_present": true,
            "parent_group_id": "%s"
        }'::jsonb
    )$$,
        :'groupAdminID',
        :'communityID',
        :'groupParentUpdateID',
        :'groupCategory1ID',
        :'parentGroupID'
    ),
    'Should update parent when the actor can manage the selected parent'
);

-- Should persist the selected parent group
select is(
    (select parent_group_id from "group" where group_id = :'groupParentUpdateID'::uuid),
    :'parentGroupID'::uuid,
    'Should persist the selected parent group'
);

-- Should record the actor in the parent update audit row
select results_eq(
    format(
        $$
        select
            action,
            actor_user_id,
            actor_username,
            details
        from audit_log
        where group_id = %L::uuid
        $$,
        :'groupParentUpdateID'
    ),
    format(
        $$ values ('group_updated', %L::uuid, 'update-group-audit-actor'::text, '{}'::jsonb) $$,
        :'groupAdminID'
    ),
    'Should record the actor in the parent update audit row'
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
            "name": "Clear Parent Group",
            "category_id": "%s",
            "parent_group_id_present": true,
            "parent_group_id": ""
        }'::jsonb
    )$$,
        :'noPermissionUserID',
        :'communityID',
        :'groupClearParentID',
        :'groupCategory1ID'
    ),
    'Should allow clearing a parent without parent-side permission'
);

-- Should clear the selected parent group
select is(
    (select parent_group_id from "group" where group_id = :'groupClearParentID'::uuid),
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

-- Should accept submitted UTM values
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "UTM Apply Group Updated",
            "category_id": "%s",
            "utm_present": true,
            "utm_campaigns": ["spring-launch"],
            "utm_mediums": ["podcast", "print"],
            "utm_sources": ["newsletter", "partner.site"]
        }'::jsonb
    )$$,
        :'communityID',
        :'groupUtmApplyID',
        :'groupCategory1ID'
    ),
    'Should accept submitted UTM values'
);

-- Should persist the submitted UTM values
select is(
    (
        select jsonb_build_object(
            'utm_campaigns', utm_campaigns,
            'utm_mediums', utm_mediums,
            'utm_sources', utm_sources
        )
        from "group"
        where group_id = :'groupUtmApplyID'::uuid
    ),
    '{
        "utm_campaigns": ["spring-launch"],
        "utm_mediums": ["podcast", "print"],
        "utm_sources": ["newsletter", "partner.site"]
    }'::jsonb,
    'Should persist the submitted UTM values'
);

-- Should accept a payload that addresses UTM values without lists
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "UTM Clear Group Updated",
            "category_id": "%s",
            "utm_present": true
        }'::jsonb
    )$$,
        :'communityID',
        :'groupUtmClearID',
        :'groupCategory1ID'
    ),
    'Should accept a payload that addresses UTM values without lists'
);

-- Should clear the UTM values omitted from a payload that addresses them
select is(
    (
        select jsonb_build_object(
            'utm_campaigns', utm_campaigns,
            'utm_mediums', utm_mediums,
            'utm_sources', utm_sources
        )
        from "group"
        where group_id = :'groupUtmClearID'::uuid
    ),
    '{
        "utm_campaigns": [],
        "utm_mediums": [],
        "utm_sources": []
    }'::jsonb,
    'Should clear the UTM values omitted from a payload that addresses them'
);

-- Should reject extra mediums that are accepted by default
select throws_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "UTM Default Medium Group Updated",
            "category_id": "%s",
            "utm_present": true,
            "utm_mediums": ["email"],
            "utm_sources": ["newsletter"]
        }'::jsonb
    )$$,
        :'communityID',
        :'groupUtmDefaultMediumID',
        :'groupCategory1ID'
    ),
    'OCG01',
    'utm mediums cannot include default mediums',
    'Should reject extra mediums that are accepted by default'
);

-- Should accept a partial payload that does not address UTM values
select lives_ok(
    format(
        $$select update_group(
        null::uuid,
        %L::uuid,
        %L::uuid,
        '{
            "name": "UTM Preserve Group Updated",
            "category_id": "%s"
        }'::jsonb
    )$$,
        :'communityID',
        :'groupUtmPreserveID',
        :'groupCategory1ID'
    ),
    'Should accept a partial payload that does not address UTM values'
);

-- Should preserve the UTM values when a partial payload does not address them
select is(
    (
        select jsonb_build_object(
            'utm_campaigns', utm_campaigns,
            'utm_mediums', utm_mediums,
            'utm_sources', utm_sources
        )
        from "group"
        where group_id = :'groupUtmPreserveID'::uuid
    ),
    '{
        "utm_campaigns": ["old-campaign"],
        "utm_mediums": ["podcast"],
        "utm_sources": ["old-source"]
    }'::jsonb,
    'Should preserve the UTM values when a partial payload does not address them'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
