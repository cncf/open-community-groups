-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set siteID '00000000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Site
insert into site (
    site_id,
    description,
    theme,
    title,

    copyright_notice,
    favicon_url,
    footer_logo_url,
    header_logo_url,
    og_image_url
) values (
    :'siteID',
    'A test site description',
    '{"primary_color":"#0066cc"}'::jsonb,
    'Test Site Title',

    'Copyright 2024 Test Site',
    'https://example.com/favicon.ico',
    'https://example.com/footer-logo.png',
    'https://example.com/header-logo.png',
    'https://example.com/og-image.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return site settings with all fields
select is(
    get_site_settings()::jsonb,
    '{
        "description": "A test site description",
        "site_id": "00000000-0000-0000-0000-000000000001",
        "theme": {"primary_color": "#0066cc"},
        "title": "Test Site Title",
        "copyright_notice": "Copyright 2024 Test Site",
        "favicon_url": "https://example.com/favicon.ico",
        "footer_logo_url": "https://example.com/footer-logo.png",
        "header_logo_url": "https://example.com/header-logo.png",
        "og_image_url": "https://example.com/og-image.png"
    }'::jsonb,
    'Should return site settings with all fields'
);

-- Should return null when no site exists
delete from site;
select ok(
    get_site_settings() is null,
    'Should return null when no site exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
