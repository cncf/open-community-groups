-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID 'ab0a0000-0000-0000-0000-000000000001'
\set community2ID 'ab0a0000-0000-0000-0000-000000000002'
\set groupCategory1ID 'ab0a0000-0000-0000-0000-000000000003'
\set groupCategory2ID 'ab0a0000-0000-0000-0000-000000000004'
\set groupConsecutiveID 'ab0a0000-0000-0000-0000-000000000005'
\set groupEdgeID 'ab0a0000-0000-0000-0000-000000000006'
\set groupGeneratedCollisionID 'ab0a0000-0000-0000-0000-000000000007'
\set groupLongID 'ab0a0000-0000-0000-0000-000000000008'
\set groupNullPrettyID 'ab0a0000-0000-0000-0000-000000000009'
\set groupOtherCommunityID 'ab0a0000-0000-0000-0000-000000000010'
\set groupPrettyCollisionID 'ab0a0000-0000-0000-0000-000000000011'
\set groupSameID 'ab0a0000-0000-0000-0000-000000000012'
\set groupUppercaseID 'ab0a0000-0000-0000-0000-000000000013'
\set groupValidID 'ab0a0000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values
    (
        :'community1ID',
        'pretty-slug-validation',
        'Pretty Slug Validation',
        'A community for pretty slug validation tests',
        'https://example.com/banner-mobile-pretty.png',
        'https://example.com/banner-pretty.png',
        'https://example.com/logo-pretty.png'
    ),
    (
        :'community2ID',
        'pretty-slug-validation-other',
        'Pretty Slug Validation Other',
        'Another community for pretty slug validation tests',
        'https://example.com/banner-mobile-pretty-other.png',
        'https://example.com/banner-pretty-other.png',
        'https://example.com/logo-pretty-other.png'
    );

-- Group categories
insert into group_category (
    group_category_id,
    community_id,
    name
) values
    (
        :'groupCategory1ID',
        :'community1ID',
        'Pretty Slug Category'
    ),
    (
        :'groupCategory2ID',
        :'community2ID',
        'Pretty Slug Category Other'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept strict ASCII pretty slugs
select lives_ok(
    format(
        'insert into "group" (group_id, community_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        :'groupValidID',
        :'community1ID',
        :'groupCategory1ID',
        'Pretty Slug Valid',
        'prettyvalid1',
        'pretty-slug-valid'
    ),
    'Should accept strict ASCII pretty slugs'
);

-- Should accept groups without a pretty slug
select lives_ok(
    format(
        'insert into "group" (group_id, community_id, group_category_id, name, slug) values (%L, %L, %L, %L, %L)',
        :'groupNullPrettyID',
        :'community1ID',
        :'groupCategory1ID',
        'Pretty Slug Null',
        'prettynull1'
    ),
    'Should accept groups without a pretty slug'
);

-- Should allow the same pretty slug in another community
select lives_ok(
    format(
        'insert into "group" (group_id, community_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        :'groupOtherCommunityID',
        :'community2ID',
        :'groupCategory2ID',
        'Pretty Slug Other Community',
        'prettyvalidother1',
        'pretty-slug-valid'
    ),
    'Should allow the same pretty slug in another community'
);

-- Should accept direct pretty slug updates
select lives_ok(
    format(
        'update "group" set slug_pretty = %L where group_id = %L',
        'pretty-slug-updated',
        :'groupNullPrettyID'
    ),
    'Should accept direct pretty slug updates'
);

-- Should reject direct pretty slug conflicts
select throws_ok(
    format(
        'update "group" set slug_pretty = %L where group_id = %L',
        'pretty-slug-valid',
        :'groupNullPrettyID'
    ),
    'P0001',
    'Pretty slug is already used by another group in this community',
    'Should reject direct pretty slug conflicts'
);

-- Should reject uppercase characters
select throws_ok(
    format(
        'insert into "group" (group_id, community_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        :'groupUppercaseID',
        :'community1ID',
        :'groupCategory1ID',
        'Pretty Slug Uppercase',
        'prettyupper1',
        'Pretty-Slug'
    ),
    'P0001',
    'Pretty slug must use lowercase ASCII letters, numbers, and hyphens only',
    'Should reject uppercase characters'
);

-- Should reject excessive length
select throws_ok(
    format(
        'insert into "group" (group_id, community_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        :'groupLongID',
        :'community1ID',
        :'groupCategory1ID',
        'Pretty Slug Long',
        'prettylong1',
        repeat('a', 51)
    ),
    'P0001',
    'Pretty slug must be 50 characters or fewer',
    'Should reject excessive length'
);

-- Should reject consecutive hyphens
select throws_ok(
    format(
        'insert into "group" (group_id, community_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        :'groupConsecutiveID',
        :'community1ID',
        :'groupCategory1ID',
        'Pretty Slug Consecutive',
        'prettyhyphen1',
        'pretty--slug'
    ),
    'P0001',
    'Pretty slug cannot contain consecutive hyphens',
    'Should reject consecutive hyphens'
);

-- Should reject leading or trailing hyphens
select throws_ok(
    format(
        'insert into "group" (group_id, community_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        :'groupEdgeID',
        :'community1ID',
        :'groupCategory1ID',
        'Pretty Slug Edge',
        'prettyedge1',
        '-pretty-slug'
    ),
    'P0001',
    'Pretty slug must start and end with a lowercase ASCII letter or number',
    'Should reject leading or trailing hyphens'
);

-- Should reject pretty slugs matching the group's generated slug
select throws_ok(
    format(
        'insert into "group" (group_id, community_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        :'groupSameID',
        :'community1ID',
        :'groupCategory1ID',
        'Pretty Slug Same',
        'prettysame1',
        'prettysame1'
    ),
    'P0001',
    'Pretty slug must be different from the generated slug',
    'Should reject pretty slugs matching the group''s generated slug'
);

-- Should reject pretty slugs matching another generated slug
select throws_ok(
    format(
        'insert into "group" (group_id, community_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        :'groupGeneratedCollisionID',
        :'community1ID',
        :'groupCategory1ID',
        'Pretty Slug Generated Collision',
        'prettygenerated1',
        'prettyvalid1'
    ),
    'P0001',
    'Pretty slug is already used by another group in this community',
    'Should reject pretty slugs matching another generated slug'
);

-- Should reject pretty slugs matching another pretty slug
select throws_ok(
    format(
        'insert into "group" (group_id, community_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        :'groupPrettyCollisionID',
        :'community1ID',
        :'groupCategory1ID',
        'Pretty Slug Pretty Collision',
        'prettypcollision1',
        'pretty-slug-valid'
    ),
    'P0001',
    'Pretty slug is already used by another group in this community',
    'Should reject pretty slugs matching another pretty slug'
);

-- Should reject generated slugs matching another pretty slug
select throws_ok(
    format(
        'update "group" set slug = %L where group_id = %L',
        'pretty-slug-valid',
        :'groupNullPrettyID'
    ),
    'P0001',
    'Pretty slug is already used by another group in this community',
    'Should reject generated slugs matching another pretty slug'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
