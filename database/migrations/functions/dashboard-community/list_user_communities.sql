-- Returns all communities where the user is a team member.
create or replace function list_user_communities(p_user_id uuid)
returns json as $$
    select coalesce(json_agg(
        get_community_summary(c.community_id)
        order by c.name asc
    ), '[]')
    from community c
    where exists (
        select 1
        from community_team ct
        where ct.user_id = p_user_id
        and ct.community_id = c.community_id
        and ct.accepted = true
    );
$$ language sql;
