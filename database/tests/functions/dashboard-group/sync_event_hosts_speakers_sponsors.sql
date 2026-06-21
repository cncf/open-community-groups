-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000011'
\set eventID '00000000-0000-0000-0000-000000000021'
\set groupCategoryID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000041'
\set otherGroupID '00000000-0000-0000-0000-000000000042'
\set otherGroupSponsorID '00000000-0000-0000-0000-000000000054'
\set sponsor1ID '00000000-0000-0000-0000-000000000051'
\set sponsor2ID '00000000-0000-0000-0000-000000000052'
\set sponsor3ID '00000000-0000-0000-0000-000000000053'
\set user1ID '00000000-0000-0000-0000-000000000061'
\set user2ID '00000000-0000-0000-0000-000000000062'
\set user3ID '00000000-0000-0000-0000-000000000063'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'allianceID', 'alliance-1', 'Alliance 1', 'Test alliance', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Group 1', 'group-1');

-- Other group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'otherGroupID', :'allianceID', :'groupCategoryID', 'Group 2', 'group-2');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Meetup');

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'user1ID', gen_random_bytes(32), 'user1@example.com', 'user1', true, 'User 1'),
    (:'user2ID', gen_random_bytes(32), 'user2@example.com', 'user2', true, 'User 2'),
    (:'user3ID', gen_random_bytes(32), 'user3@example.com', 'user3', true, 'User 3');

-- Group sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url) values
    (:'sponsor1ID', :'groupID', 'Sponsor 1', 'https://e/sponsor-1.png', null),
    (:'sponsor2ID', :'groupID', 'Sponsor 2', 'https://e/sponsor-2.png', 'https://e/sponsor-2'),
    (:'sponsor3ID', :'groupID', 'Sponsor 3', 'https://e/sponsor-3.png', null);

-- Other group sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values (:'otherGroupSponsorID', :'otherGroupID', 'Other Group Sponsor', 'https://e/sponsor-other.png', null);

-- Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values (
    :'eventID',
    :'groupID',
    'Associations Event',
    'associations-event',
    'Event used for association sync tests',
    'UTC',
    :'eventCategoryID',
    'in-person'
);

-- Existing event associations
insert into event_host (event_id, user_id)
values (:'eventID', :'user1ID');

insert into event_speaker (event_id, user_id, featured)
values (:'eventID', :'user1ID', true);

insert into event_sponsor (event_id, group_sponsor_id, level)
values (:'eventID', :'sponsor1ID', 'Gold');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should replace hosts, speakers, and sponsors from the payload
select lives_ok(
    format(
        $$select sync_event_hosts_speakers_sponsors(
            '%s'::uuid,
            '{
                "hosts": ["%s", "%s"],
                "speakers": [
                    {"user_id": "%s", "featured": false},
                    {"user_id": "%s", "featured": true}
                ],
                "sponsors": [
                    {"group_sponsor_id": "%s", "level": "Silver"},
                    {"group_sponsor_id": "%s", "level": "Bronze"}
                ]
            }'::jsonb
        )$$,
        :'eventID',
        :'user2ID',
        :'user3ID',
        :'user2ID',
        :'user3ID',
        :'sponsor2ID',
        :'sponsor3ID'
    ),
    'Should replace hosts, speakers, and sponsors from the payload'
);

-- Should replace event hosts
select is(
    (
        select array_agg(user_id order by user_id)
        from event_host
        where event_id = :'eventID'::uuid
    ),
    array[:'user2ID'::uuid, :'user3ID'::uuid],
    'Should replace event hosts'
);

-- Should replace event speakers
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'featured', featured,
                'user_id', user_id
            )
            order by user_id
        )
        from event_speaker
        where event_id = :'eventID'::uuid
    ),
    jsonb_build_array(
        jsonb_build_object('featured', false, 'user_id', :'user2ID'::uuid),
        jsonb_build_object('featured', true, 'user_id', :'user3ID'::uuid)
    ),
    'Should replace event speakers'
);

-- Should replace event sponsors
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'group_sponsor_id', group_sponsor_id,
                'level', level
            )
            order by group_sponsor_id
        )
        from event_sponsor
        where event_id = :'eventID'::uuid
    ),
    jsonb_build_array(
        jsonb_build_object('group_sponsor_id', :'sponsor2ID'::uuid, 'level', 'Silver'),
        jsonb_build_object('group_sponsor_id', :'sponsor3ID'::uuid, 'level', 'Bronze')
    ),
    'Should replace event sponsors'
);

-- Should reject sponsors that belong to a different group
select throws_ok(
    format(
        $$select sync_event_hosts_speakers_sponsors(
            '%s'::uuid,
            '{"sponsors": [{"group_sponsor_id": "%s", "level": "Gold"}]}'::jsonb
        )$$,
        :'eventID',
        :'otherGroupSponsorID'
    ),
    'sponsor does not belong to event group',
    'Should reject sponsors that belong to a different group'
);

-- Should clear omitted association sections
select lives_ok(
    format(
        $$select sync_event_hosts_speakers_sponsors(
            '%s'::uuid,
            '{"hosts": ["%s"]}'::jsonb
        )$$,
        :'eventID',
        :'user1ID'
    ),
    'Should clear omitted association sections'
);

-- Should leave only supplied hosts when speakers and sponsors are omitted
select is(
    (
        select jsonb_build_object(
            'hosts', (select count(*) from event_host where event_id = :'eventID'::uuid),
            'speakers', (select count(*) from event_speaker where event_id = :'eventID'::uuid),
            'sponsors', (select count(*) from event_sponsor where event_id = :'eventID'::uuid)
        )
    ),
    jsonb_build_object(
        'hosts', 1::bigint,
        'speakers', 0::bigint,
        'sponsors', 0::bigint
    ),
    'Should leave only supplied hosts when speakers and sponsors are omitted'
);

-- Should clear all association sections when payload is empty
select lives_ok(
    format(
        $$select sync_event_hosts_speakers_sponsors('%s'::uuid, '{}'::jsonb)$$,
        :'eventID'
    ),
    'Should clear all association sections when payload is empty'
);

-- Should leave no associations after clearing with an empty payload
select is(
    (
        select jsonb_build_object(
            'hosts', (select count(*) from event_host where event_id = :'eventID'::uuid),
            'speakers', (select count(*) from event_speaker where event_id = :'eventID'::uuid),
            'sponsors', (select count(*) from event_sponsor where event_id = :'eventID'::uuid)
        )
    ),
    jsonb_build_object(
        'hosts', 0::bigint,
        'speakers', 0::bigint,
        'sponsors', 0::bigint
    ),
    'Should leave no associations after clearing with an empty payload'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
