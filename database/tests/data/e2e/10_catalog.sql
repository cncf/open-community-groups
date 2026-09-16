-- E2E seed: catalog reference data.
-- Depends on: 00_site.sql (site settings).

-- ============================================================================
-- COMMUNITIES
-- ============================================================================

insert into community (
    community_id,
    name,
    display_name,
    description,
    ad_banner_link_url,
    ad_banner_url,
    banner_url,
    banner_mobile_url,
    logo_url
) values (
    '11111111-1111-1111-1111-111111111111',
    'e2e-test-community',
    'Platform Engineering Community',
    'Platform engineering community used for end-to-end coverage.',
    null,
    null,
    '/static/images/e2e/community-primary-banner.svg',
    '/static/images/e2e/community-primary-banner-mobile.svg',
    '/static/images/e2e/community-primary-logo.svg'
), (
    '11111111-1111-1111-1111-111111111112',
    'e2e-second-community',
    'Developer Experience Community',
    'Developer experience community used for end-to-end coverage.',
    'https://example.com/e2e-advertisement',
    '/static/images/e2e/event-banner.svg',
    '/static/images/e2e/community-secondary-banner.svg',
    '/static/images/e2e/community-secondary-banner-mobile.svg',
    '/static/images/e2e/community-secondary-logo.svg'
), (
    '11111111-1111-1111-1111-111111111113',
    'e2e-empty-community',
    'Empty Coverage Community',
    'Dedicated community for empty dashboard states.',
    null,
    null,
    '/static/images/e2e/community-secondary-banner.svg',
    '/static/images/e2e/community-secondary-banner-mobile.svg',
    '/static/images/e2e/community-secondary-logo.svg'
);

update community
set active = false
where community_id = '11111111-1111-1111-1111-111111111113';

-- Public social links and new group instructions for community page coverage.
update community
set twitter_url = 'https://twitter.com/e2e-devex',
    github_url = 'https://github.com/e2e-devex',
    linkedin_url = 'https://linkedin.com/company/e2e-devex',
    new_group_details = 'Open an issue in our GitHub organization to propose a new group.'
where community_id = '11111111-1111-1111-1111-111111111112';

-- ============================================================================
-- GROUP CATEGORIES
-- ============================================================================

insert into group_category (group_category_id, name, community_id)
values (
    '22222222-2222-2222-2222-222222222221',
    'E2E Category One',
    '11111111-1111-1111-1111-111111111111'
), (
    '22222222-2222-2222-2222-222222222222',
    'E2E Category Two',
    '11111111-1111-1111-1111-111111111112'
), (
    '22222222-2222-2222-2222-222222222223',
    'E2E Category Unused',
    '11111111-1111-1111-1111-111111111111'
);

-- ============================================================================
-- EVENT CATEGORIES
-- ============================================================================

insert into event_category (event_category_id, name, community_id)
values (
    '33333333-3333-3333-3333-333333333331',
    'General',
    '11111111-1111-1111-1111-111111111111'
), (
    '33333333-3333-3333-3333-333333333332',
    'Meetups',
    '11111111-1111-1111-1111-111111111112'
), (
    '33333333-3333-3333-3333-333333333333',
    'Workshops',
    '11111111-1111-1111-1111-111111111111'
);

-- ============================================================================
-- REGIONS
-- ============================================================================

insert into region (region_id, community_id, name, "order")
values (
    '22222222-2222-2222-2222-222222222301',
    '11111111-1111-1111-1111-111111111111',
    'North America',
    1
), (
    '22222222-2222-2222-2222-222222222302',
    '11111111-1111-1111-1111-111111111111',
    'APAC',
    2
);
