-- Tests immutable badge issuance fields and irreversible revocation timestamps.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(23);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set badgeID 'ba020000-0000-0000-0000-000000000001'
\set communityID 'ba020000-0000-0000-0000-000000000002'
\set eventCategoryID 'ba020000-0000-0000-0000-000000000003'
\set eventID 'ba020000-0000-0000-0000-000000000004'
\set groupCategoryID 'ba020000-0000-0000-0000-000000000005'
\set groupID 'ba020000-0000-0000-0000-000000000006'
\set statusListID 'ba020000-0000-0000-0000-000000000007'
\set userBadgeID 'ba020000-0000-0000-0000-000000000008'
\set userID 'ba020000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Badge recipient account
insert into "user" (auth_hash, email, email_verified, user_id, username)
values ('revocation-hash', 'revocation@example.test', true, :'userID', 'revocation-user');

-- Issuing community
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    '/mobile',
    '/banner',
    :'communityID',
    'Description',
    'Revocation Community',
    '/logo',
    'revocation-community'
);

-- Issuing group category
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Technology');

-- Issuing group retained by credential history
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Revocation Group', 'revocation-group');

-- Badge definition retained while it remains available
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'badgeID', 'Attend', 'Revocation badge', :'groupID', 'revocation.png', 'Revocation Badge');

-- Event category for the original award source
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Conferences');

-- Event retained while its original award association remains available
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    'Revocation event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Revocation Event',
    'revocation-event',
    'UTC'
);

-- Stable status list for the test award
insert into badge_status_list (badge_status_list_id, group_id)
values (:'statusListID', :'groupID');

-- Active award whose revocation state will be exercised
insert into user_badge (
    badge_status_list_id,
    display_order,
    group_id,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    user_id
) values (
    :'statusListID',
    0,
    :'groupID',
    '{"name":"Irreversible Badge"}',
    7,
    :'userBadgeID',
    :'badgeID',
    :'eventID',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow unrelated changes while the award remains active
select lives_ok(
    format($$update user_badge set is_listed = false where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'Should allow unrelated active award updates'
);

-- Should reject changing the active award timestamp
select throws_ok(
    format($$update user_badge set awarded_at = '2026-01-02 00:00:00+00' where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge issuance fields cannot be changed',
    'Should reject changing an active award timestamp'
);

-- Should reject replacing the active badge definition association
select throws_ok(
    format($$update user_badge set badge_id = gen_random_uuid() where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge issuance fields cannot be changed',
    'Should reject replacing an active badge definition association'
);

-- Should reject replacing the active event association
select throws_ok(
    format($$update user_badge set event_id = gen_random_uuid() where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge issuance fields cannot be changed',
    'Should reject replacing an active event association'
);

-- Should reject replacing the active recipient association
select throws_ok(
    format($$update user_badge set user_id = gen_random_uuid() where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge issuance fields cannot be changed',
    'Should reject replacing an active recipient association'
);

-- Should reject changing the active award status list
select throws_ok(
    format($$update user_badge set badge_status_list_id = gen_random_uuid() where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge issuance fields cannot be changed',
    'Should reject changing an active award status list'
);

-- Should reject changing the active award issuer group
select throws_ok(
    format($$update user_badge set group_id = gen_random_uuid() where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge issuance fields cannot be changed',
    'Should reject changing an active award issuer group'
);

-- Should reject changing the active award snapshot
select throws_ok(
    format($$update user_badge set snapshot = '{"name":"Changed"}' where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge issuance fields cannot be changed',
    'Should reject changing an active award snapshot'
);

-- Should reject changing the active award status index
select throws_ok(
    format($$update user_badge set status_list_index = 8 where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge issuance fields cannot be changed',
    'Should reject changing an active award status index'
);

-- Should reject changing the active award identifier
select throws_ok(
    format($$update user_badge set user_badge_id = gen_random_uuid() where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge issuance fields cannot be changed',
    'Should reject changing an active award identifier'
);

-- Should allow the first revocation timestamp to be recorded
select lives_ok(
    format(
        $$
        update user_badge
        set
            revocation_reason = 'policy violation',
            revoked_at = '2026-01-01 00:00:00+00',
            revoked_by_user_id = %L::uuid
        where user_badge_id = %L::uuid
        $$,
        :'userID',
        :'userBadgeID'
    ),
    'Should allow the first revocation'
);

-- Should reject clearing an existing revocation timestamp
select throws_ok(
    format($$update user_badge set revoked_at = null where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge revocation cannot be changed',
    'Should reject clearing a revocation'
);

-- Should reject replacing an existing revocation timestamp
select throws_ok(
    format($$update user_badge set revoked_at = '2026-01-02 00:00:00+00' where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge revocation cannot be changed',
    'Should reject changing a revocation timestamp'
);

-- Should reject listing a revoked award
select throws_ok(
    format($$update user_badge set is_listed = true where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'revoked badge cannot be listed',
    'Should reject listing a revoked award'
);

-- Should reject changing a recorded revocation reason
select throws_ok(
    format($$update user_badge set revocation_reason = 'changed' where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge revocation metadata cannot be changed',
    'Should reject changing a recorded revocation reason'
);

-- Should reject replacing a recorded revocation actor
select throws_ok(
    format($$update user_badge set revoked_by_user_id = gen_random_uuid() where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'badge revocation metadata cannot be changed',
    'Should reject replacing a recorded revocation actor'
);

-- Should allow a deleted revocation actor foreign key to be cleared
select lives_ok(
    format($$update user_badge set revoked_by_user_id = null where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'Should allow clearing a deleted revocation actor'
);

-- Should reject replacing a cleared revocation actor
select throws_ok(
    format($$update user_badge set revoked_by_user_id = %L::uuid where user_badge_id = %L::uuid$$, :'userID', :'userBadgeID'),
    'badge revocation metadata cannot be changed',
    'Should reject replacing a cleared revocation actor'
);

-- Should allow deletion cascades to clear optional issuance associations
select lives_ok(
    format(
        $$
        update user_badge
        set badge_id = null, event_id = null, user_id = null
        where user_badge_id = %L::uuid
        $$,
        :'userBadgeID'
    ),
    'Should allow optional issuance associations to be cleared'
);

-- Should reject reattaching a cleared badge definition association
select throws_ok(
    format($$update user_badge set badge_id = %L::uuid where user_badge_id = %L::uuid$$, :'badgeID', :'userBadgeID'),
    'badge issuance fields cannot be changed',
    'Should reject reattaching a cleared badge definition association'
);

-- Should reject reattaching a cleared event association
select throws_ok(
    format($$update user_badge set event_id = %L::uuid where user_badge_id = %L::uuid$$, :'eventID', :'userBadgeID'),
    'badge issuance fields cannot be changed',
    'Should reject reattaching a cleared event association'
);

-- Should reject reattaching a cleared recipient association
select throws_ok(
    format($$update user_badge set user_id = %L::uuid where user_badge_id = %L::uuid$$, :'userID', :'userBadgeID'),
    'badge issuance fields cannot be changed',
    'Should reject reattaching a cleared recipient association'
);

-- Should allow unrelated changes after revocation
select lives_ok(
    format($$update user_badge set display_order = 1 where user_badge_id = %L::uuid$$, :'userBadgeID'),
    'Should allow unrelated revoked award updates'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
