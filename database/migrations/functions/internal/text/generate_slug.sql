-- Generates random alphanumeric codes for use as slugs.
-- Uses character set excluding ambiguous characters (0, o, 1, l, i).
create or replace function generate_slug(p_length int default 7)
returns text language sql as $$
    select string_agg(
        substr('23456789abcdefghjkmnpqrstuvwxyz', floor(random() * 31 + 1)::int, 1),
        ''
    )
    from generate_series(1, p_length)
$$;
