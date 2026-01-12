-- Accepts a pending group team invitation for a user.
create or replace function accept_group_team_invitation(p_group_id uuid, p_user_id uuid)
returns void as $$
begin
    update group_team gt
    set accepted = true
    where gt.group_id = p_group_id
      and gt.user_id = p_user_id
      and gt.accepted = false;

    if not found then
        raise exception 'no pending group invitation found';
    end if;
end;
$$ language plpgsql;
