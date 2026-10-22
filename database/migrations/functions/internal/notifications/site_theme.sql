-- Returns the theme of the latest site configuration used by notifications.
create or replace function site_theme()
returns jsonb as $$
    select s.theme
    from site s
    order by s.created_at desc
    limit 1;
$$ language sql stable;
