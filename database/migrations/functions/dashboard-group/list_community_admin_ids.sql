-- Returns accepted, email-verified community admin user ids.
create or replace function list_community_admin_ids(p_community_id uuid)
returns uuid[] as $$
    select coalesce(array_agg(ct.user_id order by ct.user_id asc), array[]::uuid[])
    from community_team ct
    join "user" u using (user_id)
    where ct.community_id = p_community_id
    and ct.accepted = true
    and ct.role = 'admin'
    and u.email_verified = true;
$$ language sql;
