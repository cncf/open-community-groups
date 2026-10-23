-- Approves a pending event co-host invitation.
create or replace function approve_event_cohost(
    p_actor_user_id uuid,
    p_cohost_group_id uuid,
    p_invitation_id uuid
)
returns json as $$
    select transition_event_cohost(p_actor_user_id, p_cohost_group_id, p_invitation_id, 'approved');
$$ language sql volatile;
