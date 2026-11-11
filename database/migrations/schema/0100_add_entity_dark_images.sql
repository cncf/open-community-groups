-- Adds dark mode variants of the community, group and event images.

-- Bound lock waits so the migration fails instead of stalling the app.
set local lock_timeout = '5s';

-- Dark mode variants of the community images, each shown in the slot of its
-- light counterpart at the same size
alter table community
    -- Dark mode banner. It is used only together with banner_url; without
    -- it, dark mode shows the light banner.
    add column banner_dark_url text
        check (btrim(banner_dark_url) <> ''),
    -- Dark mode mobile banner. It is used only together with
    -- banner_mobile_url; without it, dark mode shows the light mobile banner.
    add column banner_mobile_dark_url text
        check (btrim(banner_mobile_dark_url) <> ''),
    -- Dark mode logo. It is used only together with logo_url; without it,
    -- dark mode shows the light logo on a white plate.
    add column logo_dark_url text
        check (btrim(logo_dark_url) <> '');

-- Dark mode variants of the group images, each shown in the slot of its light
-- counterpart at the same size and never paired with a community fallback
alter table "group"
    -- Dark mode banner. It is used only together with the group's own
    -- banner_url; without it, dark mode shows the light banner.
    add column banner_dark_url text
        check (btrim(banner_dark_url) <> ''),
    -- Dark mode mobile banner. It is used only together with the group's own
    -- banner_mobile_url; without it, dark mode shows the light mobile banner.
    add column banner_mobile_dark_url text
        check (btrim(banner_mobile_dark_url) <> ''),
    -- Dark mode logo. It is used only together with the group's own logo_url;
    -- without it, dark mode shows the light logo on a white plate.
    add column logo_dark_url text
        check (btrim(logo_dark_url) <> '');

-- Dark mode variants of the event images, each shown in the slot of its light
-- counterpart at the same size and never paired with a group or community
-- fallback
alter table event
    -- Dark mode banner. It is used only together with the event's own
    -- banner_url; without it, dark mode shows the light banner.
    add column banner_dark_url text
        check (btrim(banner_dark_url) <> ''),
    -- Dark mode mobile banner. It is used only together with the event's own
    -- banner_mobile_url; without it, dark mode shows the light mobile banner.
    add column banner_mobile_dark_url text
        check (btrim(banner_mobile_dark_url) <> ''),
    -- Dark mode logo. It is used only together with the event's own logo_url;
    -- without it, dark mode shows the light logo on a white plate.
    add column logo_dark_url text
        check (btrim(logo_dark_url) <> '');
