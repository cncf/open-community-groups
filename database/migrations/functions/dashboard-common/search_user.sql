-- search_user searches for users by username or name prefix, or by exact
-- email match.
create or replace function search_user(p_query text)
returns jsonb as $$
    select coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb)
    from (
        select
            u.user_id,
            u.username,

            u.name,
            u.photo_url
        from "user" u
        where u.email_verified = true
        and u.registration_status = 'registered'
        and p_query <> ''
        and (
            u.username ilike escape_ilike_pattern(p_query) || '%' escape '\'
            or u.name ilike escape_ilike_pattern(p_query) || '%' escape '\'
            or lower(u.email) = lower(p_query)
        )
        order by u.username
        limit 5
    ) t
$$ language sql;
