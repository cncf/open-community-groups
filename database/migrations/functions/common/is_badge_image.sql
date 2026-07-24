-- Returns whether a file is retained by current or historical badge data.
create or replace function is_badge_image(p_file_name text)
returns boolean as $$
    select exists (
        select 1
        from badge_artwork
        where file_name = p_file_name
    )
    or exists (
        select 1
        from badge
        where image_file_name = p_file_name
    )
    or exists (
        select 1
        from user_badge
        where snapshot->>'image_file_name' = p_file_name
    );
$$ language sql;
