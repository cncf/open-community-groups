-- E2E seed: site settings.
-- Depends on: base schema only.

-- ============================================================================
-- SITE
-- ============================================================================

insert into site (
    site_id,
    title,
    description,
    favicon_url,
    theme
) values (
    '00000000-0000-0000-0000-000000000000',
    'E2E Test Site',
    'Site for E2E testing',
    'https://static.example.com/e2e/favicon.ico',
    '{"primary_color": "#0EA5E9"}'::jsonb
);
