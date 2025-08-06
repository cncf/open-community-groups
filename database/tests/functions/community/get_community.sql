-- Start transaction and plan tests
begin;
select plan(1);

-- Declare some variables
\set community1ID '00000000-0000-0000-0000-000000000001'

-- Seed community
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme,
    facebook_url,
    twitter_url,
    website_url
) values (
    :'community1ID',
    'test-community',
    'Test Community',
    'test.localhost',
    'Test Community Title',
    'A test community for testing purposes',
    'https://example.com/logo.png',
    '{"primary_color": "#FF0000"}'::jsonb,
    'https://facebook.com/testcommunity',
    'https://twitter.com/testcommunity',
    'https://example.com'
);

-- Test get_community function returns correct data
select is(
    get_community('00000000-0000-0000-0000-000000000001'::uuid)::jsonb,
    '{
        "name": "test-community",
        "display_name": "Test Community",
        "title": "Test Community Title",
        "description": "A test community for testing purposes",
        "header_logo_url": "https://example.com/logo.png",
        "theme": {"primary_color": "#FF0000"},
        "facebook_url": "https://facebook.com/testcommunity",
        "twitter_url": "https://twitter.com/testcommunity",
        "website_url": "https://example.com"
    }'::jsonb,
    'get_community should return correct community data as JSON'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;