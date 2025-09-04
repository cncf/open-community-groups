-- Accepts a pending group team invitation for a user.
create or replace function accept_group_team_invitation(
    p_community_id uuid,
    p_group_id uuid,
    p_user_id uuid
) returns void as $$
begin
    update group_team gt
    set accepted = true
    where gt.group_id = p_group_id
      and gt.user_id = p_user_id
      and gt.accepted = false
      and exists (
          select 1 from "group" g
          where g.group_id = gt.group_id
            and g.community_id = p_community_id
      );

    if not found then
        raise exception 'no pending group invitation found';
    end if;
end;
$$ language plpgsql;
