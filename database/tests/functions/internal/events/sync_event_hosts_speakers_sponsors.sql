-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a330000-0000-0000-0000-000000000001'
\set eventCategoryID '3a330000-0000-0000-0000-000000000002'
\set eventID '3a330000-0000-0000-0000-000000000003'
\set groupCategoryID '3a330000-0000-0000-0000-000000000004'
\set groupID '3a330000-0000-0000-0000-000000000005'
\set otherGroupID '3a330000-0000-0000-0000-000000000006'
\set otherGroupSponsorID '3a330000-0000-0000-0000-000000000007'
\set sponsor1ID '3a330000-0000-0000-0000-000000000008'
\set sponsor2ID '3a330000-0000-0000-0000-000000000009'
\set sponsor3ID '3a330000-0000-0000-0000-000000000010'
\set user1ID '3a330000-0000-0000-0000-000000000011'
\set user2ID '3a330000-0000-0000-0000-000000000012'
\set user3ID '3a330000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, groups and events
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Users
select fx_user(:'user1ID', jsonb_build_object('username', 'user1-sync-event-hosts-speakers-sponsors'));
select fx_user(:'user2ID', jsonb_build_object('username', 'user2-sync-event-hosts-speakers-sponsors'));
select fx_user(:'user3ID', jsonb_build_object('username', 'user3-sync-event-hosts-speakers-sponsors'));

-- Group sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url) values
    (:'sponsor1ID', :'groupID', 'Sponsor 1', 'https://e/sponsor-1.png', null),
    (:'sponsor2ID', :'groupID', 'Sponsor 2', 'https://e/sponsor-2.png', 'https://e/sponsor-2'),
    (:'sponsor3ID', :'groupID', 'Sponsor 3', 'https://e/sponsor-3.png', null);

-- Other group sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values (
    :'otherGroupSponsorID',
    :'otherGroupID',
    'Other Group Sponsor',
    'https://e/sponsor-other.png',
    null
);

-- Existing event associations
insert into event_host (event_id, user_id)
values (:'eventID', :'user1ID');

-- Existing event speaker retained by synchronization
insert into event_speaker (event_id, user_id, featured)
values (:'eventID', :'user1ID', true);

-- Existing event sponsor retained by synchronization
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
    'OCG01',
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
