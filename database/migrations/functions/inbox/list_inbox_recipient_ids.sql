-- Returns the accepted, email-verified group team members whose role grants
-- inbox access, who are emailed when a user writes to the group.
create or replace function list_inbox_recipient_ids(p_group_id uuid)
returns uuid[] as $$
    select coalesce(array_agg(gt.user_id order by gt.user_id asc), array[]::uuid[])
    from group_team gt
    join "user" u on u.user_id = gt.user_id
    join group_role_group_permission grgp on grgp.group_role_id = gt.role
    where gt.group_id = p_group_id
    and gt.accepted = true
    and u.email_verified = true
    and grgp.group_permission_id = 'group.inbox.write';
$$ language sql stable;
