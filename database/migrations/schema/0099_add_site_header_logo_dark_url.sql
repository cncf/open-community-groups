-- Adds the dark mode site header logo.

-- Bound lock waits so the migration fails instead of stalling the app.
set local lock_timeout = '5s';

-- Dark mode logo for the site header, shown in the header_logo_url slot
-- at the same size. It is used only together with header_logo_url;
-- without it, dark mode shows the light logo on a white plate.
alter table site
    add column header_logo_dark_url text
        check (btrim(header_logo_dark_url) <> '');
