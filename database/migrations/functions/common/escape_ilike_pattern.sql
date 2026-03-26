-- escape_ilike_pattern escapes ILIKE metacharacters for literal substring search.
create or replace function escape_ilike_pattern(p_value text)
returns text as $$
    select replace(
        replace(
            replace(p_value, '\', '\\'),
            '%',
            '\%'
        ),
        '_',
        '\_'
    );
$$ language sql immutable;
