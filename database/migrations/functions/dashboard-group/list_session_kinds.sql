-- list_session_kinds returns all available session kinds.
create or replace function list_session_kinds()
returns json as $$
    select coalesce(
        json_agg(
            json_build_object(
                'session_kind_id', sk.session_kind_id,
                'display_name', sk.display_name
            )
            order by sk.session_kind_id
        ),
        '[]'
    )
    from session_kind sk;
$$ language sql;
