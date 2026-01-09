-- Returns the site settings.
create or replace function get_site_settings()
returns json as $$
    select json_strip_nulls(json_build_object(
        'description', description,
        'site_id', site_id,
        'theme', theme,
        'title', title,

        'copyright_notice', copyright_notice,
        'favicon_url', favicon_url,
        'footer_logo_url', footer_logo_url,
        'header_logo_url', header_logo_url,
        'og_image_url', og_image_url
    ))
    from site
    limit 1;
$$ language sql;
