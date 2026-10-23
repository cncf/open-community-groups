-- Checks whether a community team has an accepted admin other than the given user.
-- Callers lock the community team rows first, so the answer holds until commit.
create or replace function community_team_has_other_accepted_admin(
    p_community_id uuid,
    p_user_id uuid
)
returns boolean as $$
    select exists (
        select 1
        from community_team ct
        where ct.community_id = p_community_id
          and ct.accepted = true
          and ct.role = 'admin'
          and ct.user_id <> p_user_id
    );
$$ language sql stable;
