-- search_user searches for users by username, name, or email within a community.
create or replace function search_user(
    p_community_id uuid,
    p_query text
)
returns jsonb as $$
    select coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb)
    from (
        select
            u.user_id,
            u.username,

            u.name,
            u.photo_url
        from "user" u
        where u.community_id = p_community_id
        and u.email_verified = true
        and p_query <> ''
        and (
            u.username ilike replace(replace(p_query, '%', '\%'), '_', '\_') || '%' escape '\'
            or u.name ilike replace(replace(p_query, '%', '\%'), '_', '\_') || '%' escape '\'
            or u.email ilike replace(replace(p_query, '%', '\%'), '_', '\_') || '%' escape '\'
        )
        order by u.username
        limit 5
    ) t
$$ language sql;
