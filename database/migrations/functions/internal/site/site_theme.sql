-- Returns the theme of the single site configuration, used by site reads and
-- notifications. Returns null when no site configuration exists.
create or replace function site_theme()
returns jsonb as $$
    select s.theme from site s;
$$ language sql stable;
