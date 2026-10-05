-- Searches verified users by username, name prefix, or exact email.
-- Uses PL/pgSQL with custom plans so the lowercase prefix patterns are planned
-- as constants and can use the lowercase pattern indexes on "user".
create or replace function search_user(p_query text)
returns jsonb as $$
begin
    return (
        select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.username), '[]'::jsonb)
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
                lower(u.username) like lower(escape_ilike_pattern(p_query)) || '%' escape '\'
                or lower(u.name) like lower(escape_ilike_pattern(p_query)) || '%' escape '\'
                or lower(u.email) = lower(p_query)
            )
            order by u.username
            limit 5
        ) t
    );
end;
$$ language plpgsql set plan_cache_mode = force_custom_plan;
