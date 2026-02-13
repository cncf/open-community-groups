-- Generates deterministic alphanumeric codes from a source string.
-- Uses character set excluding ambiguous characters (0, o, 1, l, i).
create or replace function generate_slug_from_source(p_source text, p_length int default 7)
returns text language sql immutable as $$
    select string_agg(
        substr(
            '23456789abcdefghjkmnpqrstuvwxyz',
            (get_byte(digest(p_source || ':' || s.i::text, 'sha256'), 0) % 31) + 1,
            1
        ),
        ''
    )
    from generate_series(1, p_length) as s(i)
$$;
