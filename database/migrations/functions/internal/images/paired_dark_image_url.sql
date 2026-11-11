-- Returns the dark mode variant paired with an image that cascades over up to
-- three levels, such as event, group and community. The light image comes
-- from the first level with a light URL, and only that level's dark URL is
-- returned: a level whose light image has no dark variant yields null instead
-- of taking another level's dark image, and a dark URL on a level without a
-- light one is ignored.
create or replace function paired_dark_image_url(
    p_first_light_url text,
    p_first_dark_url text,
    p_second_light_url text default null,
    p_second_dark_url text default null,
    p_third_light_url text default null,
    p_third_dark_url text default null
)
returns text as $$
    select case
        -- Use the first level's dark image when it provides the light image
        when p_first_light_url is not null then p_first_dark_url
        -- Use the second level's dark image when it provides the light image
        when p_second_light_url is not null then p_second_dark_url
        -- Use the third level's dark image when it provides the light image
        when p_third_light_url is not null then p_third_dark_url
        -- Otherwise there is no light image to pair a dark one with
        else null
    end;
$$ language sql immutable;
