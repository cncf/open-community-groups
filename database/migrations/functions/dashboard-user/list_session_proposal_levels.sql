-- Returns all available session proposal levels.
create or replace function list_session_proposal_levels()
returns json as $$
    select coalesce(
        json_agg(
            json_build_object(
                'display_name', spl.display_name,
                'session_proposal_level_id', spl.session_proposal_level_id
            )
            order by spl.session_proposal_level_id
        ),
        '[]'::json
    )
    from session_proposal_level spl;
$$ language sql;
