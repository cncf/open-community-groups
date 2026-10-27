-- Checks whether a community has at least one publicly visible group.
create or replace function community_has_public_group(p_community_id uuid)
returns boolean as $$
    select exists (
        select 1
        from "group" g
        where g.community_id = p_community_id
          and is_group_public(g)
    );
$$ language sql stable;
