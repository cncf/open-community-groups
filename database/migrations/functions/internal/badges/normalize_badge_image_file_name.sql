-- Normalizes a badge image value to the bare file name that badge definitions
-- and gallery entries store: surrounding whitespace and an /images/ or
-- /images/badges/ prefix are removed, and blank values become null.
create or replace function normalize_badge_image_file_name(p_value text)
returns text as $$
    select nullif(btrim(regexp_replace(btrim(p_value), '^/images/(badges/)?', '')), '');
$$ language sql immutable;
