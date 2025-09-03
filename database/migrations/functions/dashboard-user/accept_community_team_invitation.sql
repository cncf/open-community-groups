-- Accepts a pending community team invitation for a user.
create or replace function accept_community_team_invitation(
    p_community_id uuid,
    p_user_id uuid
) returns void as $$
    update community_team
    set accepted = true
    where community_id = $1
      and user_id = $2;
$$ language sql;
