-- Builds a full-text query from user input where every lexeme also matches
-- as a prefix, so partially typed words find their completions.
create or replace function prefix_tsquery(p_config regconfig, p_query text)
returns tsquery as $$
    select ts_rewrite(
        websearch_to_tsquery(p_config, p_query),
        format(
            'select to_tsquery(%L, lexeme), to_tsquery(%L, lexeme || '':*'')
             from unnest(tsvector_to_array(to_tsvector(%L, %L))) as lexeme',
            p_config::text,
            p_config::text,
            p_config::text,
            p_query
        )
    );
$$ language sql stable;
