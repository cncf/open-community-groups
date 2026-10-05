-- Returns paginated group members with join date and basic profile info.
-- Uses PL/pgSQL with custom plans so pagination bounds are planned as
-- constants and large groups walk the member order index on "user".
create or replace function list_group_members(p_group_id uuid, p_filters jsonb)
returns json as $$
declare
    v_limit int;
    v_offset int;
begin
    -- Resolve pagination bounds so the planner sees concrete values
    select f.limit_value, f.offset_value
    into v_limit, v_offset
    from parse_search_filters(p_filters) f;

    -- Select the requested page in display order, then attach join dates
    return (
        with members as (
            select
                gm.created_at,
                u.company,
                u.name,
                u.photo_url,
                u.title,
                u.user_id,
                u.username
            from (
                select
                    u.company,
                    u.name,
                    u.photo_url,
                    u.title,
                    u.user_id,
                    u.username
                from "user" u
                where exists (
                    select 1
                    from group_member gm
                    where gm.group_id = p_group_id
                    and gm.user_id = u.user_id
                )
                order by (u.name is not null) desc, lower(u.name), lower(u.username), u.user_id
                offset v_offset
                limit v_limit
            ) u
            join group_member gm on gm.group_id = p_group_id and gm.user_id = u.user_id
        )
        select json_build_object(
            'members', (
                select coalesce(
                    json_agg(
                        (
                            select row_to_json(member)
                            from (
                                select
                                    epoch_seconds(m.created_at) as created_at,
                                    m.username,

                                    m.company,
                                    m.name,
                                    m.photo_url,
                                    m.title
                            ) member
                        )
                        order by (m.name is not null) desc, lower(m.name), lower(m.username), m.user_id
                    ),
                    '[]'::json
                )
                from members m
            ),
            'total', (
                select count(*)::int
                from group_member gm
                where gm.group_id = p_group_id
            )
        )
    );
end;
$$ language plpgsql stable set plan_cache_mode = force_custom_plan;
