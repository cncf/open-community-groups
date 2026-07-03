-- request_group_member_phone records a member's request to view another member's phone number.
create or replace function request_group_member_phone(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_recipient_user_id uuid
) returns void language plpgsql as $$
begin
    if p_actor_user_id = p_recipient_user_id then
        raise exception 'you cannot request your own phone number';
    end if;

    if not exists (
        select 1
        from group_member
        where group_id = p_group_id
          and user_id = p_actor_user_id
    ) then
        raise exception 'requester is not a group member';
    end if;

    if not exists (
        select 1
        from group_member gm
        join "user" u using (user_id)
        where gm.group_id = p_group_id
          and gm.user_id = p_recipient_user_id
          and nullif(trim(u.phone_number), '') is not null
          and nullif(trim(u.phone_country_code), '') is not null
    ) then
        raise exception 'recipient phone number is unavailable';
    end if;

    insert into group_member_phone_request (
        group_id,
        requester_user_id,
        recipient_user_id,
        status
    ) values (
        p_group_id,
        p_actor_user_id,
        p_recipient_user_id,
        'pending'
    )
    on conflict (group_id, requester_user_id, recipient_user_id)
    do update set
        status = case
            when group_member_phone_request.status = 'approved' then 'approved'
            else 'pending'
        end,
        updated_at = current_timestamp;
end;
$$;
