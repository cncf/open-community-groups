-- Returns the number of pending dashboard invitations a user can act on.
create or replace function count_user_pending_invitations(p_user_id uuid)
returns bigint as $$
    select
        (
            select count(*)
            from alliance_team ct
            where ct.user_id = p_user_id
              and ct.accepted = false
        ) +
        (
            select count(*)
            from event_attendee ea
            join event e using (event_id)
            join "group" g using (group_id)
            where ea.user_id = p_user_id
              and ea.status = 'invitation-pending'
              and g.active = true
              and e.deleted = false
              and e.published = true
              and e.canceled = false
              and (
                  coalesce(e.ends_at, e.starts_at) is null
                  or coalesce(e.ends_at, e.starts_at) >= current_timestamp
              )
        ) +
        (
            select count(*)
            from group_team gt
            where gt.user_id = p_user_id
              and gt.accepted = false
        );
$$ language sql;
