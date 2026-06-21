-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000611'
\set category2ID '00000000-0000-0000-0000-000000000612'
\set alliance1ID '00000000-0000-0000-0000-000000000610'
\set alliance2ID '00000000-0000-0000-0000-000000000620'
\set groupValidID '00000000-0000-0000-0000-000000000601'
\set groupNullPrettyID '00000000-0000-0000-0000-000000000602'

-- ============================================================================
-- SEED DATA
-- ============================================================================

insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (
        :'alliance1ID',
        'pretty-slug-validation',
        'Pretty Slug Validation',
        'A alliance for pretty slug validation tests',
        'https://example.com/logo-pretty.png',
        'https://example.com/banner-mobile-pretty.png',
        'https://example.com/banner-pretty.png'
    ),
    (
        :'alliance2ID',
        'pretty-slug-validation-other',
        'Pretty Slug Validation Other',
        'Another alliance for pretty slug validation tests',
        'https://example.com/logo-pretty-other.png',
        'https://example.com/banner-mobile-pretty-other.png',
        'https://example.com/banner-pretty-other.png'
    );

insert into group_category (
    group_category_id,
    alliance_id,
    name
) values
    (
        :'category1ID',
        :'alliance1ID',
        'Pretty Slug Category'
    ),
    (
        :'category2ID',
        :'alliance2ID',
        'Pretty Slug Category Other'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept strict ASCII pretty slugs
select lives_ok(
    format(
        'insert into "group" (group_id, alliance_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        :'groupValidID',
        :'alliance1ID',
        :'category1ID',
        'Pretty Slug Valid',
        'prettyvalid1',
        'pretty-slug-valid'
    ),
    'Should accept strict ASCII pretty slugs'
);

-- Should accept groups without a pretty slug
select lives_ok(
    format(
        'insert into "group" (group_id, alliance_id, group_category_id, name, slug) values (%L, %L, %L, %L, %L)',
        :'groupNullPrettyID',
        :'alliance1ID',
        :'category1ID',
        'Pretty Slug Null',
        'prettynull1'
    ),
    'Should accept groups without a pretty slug'
);

-- Should allow the same pretty slug in another alliance
select lives_ok(
    format(
        'insert into "group" (group_id, alliance_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        '00000000-0000-0000-0000-000000000621',
        :'alliance2ID',
        :'category2ID',
        'Pretty Slug Other Alliance',
        'prettyvalidother1',
        'pretty-slug-valid'
    ),
    'Should allow the same pretty slug in another alliance'
);

-- Should reject uppercase characters
select throws_ok(
    format(
        'insert into "group" (group_id, alliance_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        '00000000-0000-0000-0000-000000000603',
        :'alliance1ID',
        :'category1ID',
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
        'insert into "group" (group_id, alliance_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        '00000000-0000-0000-0000-000000000604',
        :'alliance1ID',
        :'category1ID',
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
        'insert into "group" (group_id, alliance_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        '00000000-0000-0000-0000-000000000605',
        :'alliance1ID',
        :'category1ID',
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
        'insert into "group" (group_id, alliance_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        '00000000-0000-0000-0000-000000000606',
        :'alliance1ID',
        :'category1ID',
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
        'insert into "group" (group_id, alliance_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        '00000000-0000-0000-0000-000000000607',
        :'alliance1ID',
        :'category1ID',
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
        'insert into "group" (group_id, alliance_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        '00000000-0000-0000-0000-000000000608',
        :'alliance1ID',
        :'category1ID',
        'Pretty Slug Generated Collision',
        'prettygenerated1',
        'prettyvalid1'
    ),
    'P0001',
    'Pretty slug is already used by another group in this alliance',
    'Should reject pretty slugs matching another generated slug'
);

-- Should reject pretty slugs matching another pretty slug
select throws_ok(
    format(
        'insert into "group" (group_id, alliance_id, group_category_id, name, slug, slug_pretty) values (%L, %L, %L, %L, %L, %L)',
        '00000000-0000-0000-0000-000000000609',
        :'alliance1ID',
        :'category1ID',
        'Pretty Slug Pretty Collision',
        'prettypcollision1',
        'pretty-slug-valid'
    ),
    'P0001',
    'Pretty slug is already used by another group in this alliance',
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
    'Pretty slug is already used by another group in this alliance',
    'Should reject generated slugs matching another pretty slug'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
