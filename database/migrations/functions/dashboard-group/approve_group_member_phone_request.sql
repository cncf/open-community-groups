-- approve_group_member_phone_request lets a member reveal their phone number to a requester.
create or replace function approve_group_member_phone_request(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_requester_user_id uuid
) returns void language plpgsql as $$
begin
    update group_member_phone_request
    set
        status = 'approved',
        updated_at = current_timestamp
    where group_id = p_group_id
      and requester_user_id = p_requester_user_id
      and recipient_user_id = p_actor_user_id
      and status = 'pending';

    if not found then
        raise exception 'phone request not found';
    end if;
end;
$$;
