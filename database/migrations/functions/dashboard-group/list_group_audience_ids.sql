-- Returns the verified members and accepted, verified team members of a group, deduplicated and sorted.
create or replace function list_group_audience_ids(p_group_id uuid)
returns uuid[] as $$
    select coalesce(array_agg(audience.user_id order by audience.user_id asc), array[]::uuid[])
    from (
        -- Verified group members
        select gm.user_id
        from group_member gm
        join "user" u using (user_id)
        where gm.group_id = p_group_id
        and u.email_verified = true

        union

        -- Accepted, verified group team members
        select gt.user_id
        from group_team gt
        join "user" u using (user_id)
        where gt.group_id = p_group_id
        and gt.accepted = true
        and u.email_verified = true
    ) audience;
$$ language sql stable;
