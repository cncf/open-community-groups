-- Checks whether a group team has an accepted admin other than the given user.
-- Callers lock the group team rows first, so the answer holds until commit.
create or replace function group_team_has_other_accepted_admin(
    p_group_id uuid,
    p_user_id uuid
)
returns boolean as $$
    select exists (
        select 1
        from group_team gt
        where gt.group_id = p_group_id
          and gt.accepted = true
          and gt.role = 'admin'
          and gt.user_id <> p_user_id
    );
$$ language sql stable;
