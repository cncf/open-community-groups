-- Lists the groups in a group's public scope: the group itself when it is
-- publicly visible in the community, plus its publicly visible subgroups when
-- requested. A hidden group has an empty scope.
create or replace function list_group_scope_ids(
    p_community_id uuid,
    p_group_id uuid,
    p_include_subgroups boolean
)
returns table (group_id uuid) as $$
    with
    -- Resolve the publicly visible target group in the community
    target_group as (
        select g.group_id
        from "group" g
        where g.community_id = p_community_id
        and g.group_id = p_group_id
        and is_group_public(g)
    )
    -- Return the target group and, when requested, its public subgroups
    select tg.group_id
    from target_group tg

    union all

    select child.group_id
    from "group" child
    join target_group tg on child.parent_group_id = tg.group_id
    where p_include_subgroups
    and child.community_id = p_community_id
    and is_group_public(child);
$$ language sql stable;
