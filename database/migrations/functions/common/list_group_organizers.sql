-- Returns the accepted team members of a group in team order.
create or replace function list_group_organizers(p_group_id uuid)
returns json as $$
    select coalesce(
        json_agg(public_user_profile(u) order by gt."order" nulls last, u.name),
        '[]'
    )
    from group_team gt
    join "user" u using (user_id)
    where gt.group_id = p_group_id
    and gt.accepted = true;
$$ language sql stable;
