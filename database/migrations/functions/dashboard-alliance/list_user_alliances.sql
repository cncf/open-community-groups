-- Returns all alliances where the user is a team member.
create or replace function list_user_alliances(p_user_id uuid)
returns json as $$
    select coalesce(json_agg(
        get_alliance_summary(c.alliance_id)
        order by c.name asc
    ), '[]')
    from alliance c
    where exists (
        select 1
        from alliance_team ct
        where ct.user_id = p_user_id
        and ct.alliance_id = c.alliance_id
        and ct.accepted = true
    );
$$ language sql;
