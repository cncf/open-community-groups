-- add_coffee_meet_request records a direct coffee request and returns email metadata.
create or replace function add_coffee_meet_request(
    p_requester_user_id uuid,
    p_recipient_username text,
    p_input jsonb
) returns jsonb language plpgsql as $$
declare
    v_message text := nullif(trim(p_input->>'message'), '');
    v_recipient record;
    v_requester record;
    v_request_id uuid;
    v_request_count int;
begin
    if v_message is null then
        raise exception 'message is required';
    end if;

    select
        user_id,
        email,
        username,
        name
    into v_recipient
    from "user"
    where lower(username) = lower(p_recipient_username)
      and email_verified = true
      and registration_status = 'registered';

    if v_recipient.user_id is null then
        raise exception 'member not found';
    end if;

    if v_recipient.user_id = p_requester_user_id then
        raise exception 'you cannot request coffee from yourself';
    end if;

    select user_id, email, username, name
    into v_requester
    from "user"
    where user_id = p_requester_user_id
      and email_verified = true
      and registration_status = 'registered';

    if v_requester.user_id is null then
        raise exception 'requester not found';
    end if;

    insert into coffee_meet_request (
        recipient_user_id,
        requester_user_id,
        message
    ) values (
        v_recipient.user_id,
        v_requester.user_id,
        v_message
    )
    returning coffee_meet_request_id into v_request_id;

    select count(*)::int
    into v_request_count
    from coffee_meet_request
    where recipient_user_id = v_recipient.user_id;

    return jsonb_build_object(
        'coffee_meet_request_id', v_request_id,
        'recipient_user_id', v_recipient.user_id,
        'recipient_email', v_recipient.email,
        'recipient_username', v_recipient.username,
        'recipient_name', v_recipient.name,
        'requester_user_id', v_requester.user_id,
        'requester_email', v_requester.email,
        'requester_username', v_requester.username,
        'requester_name', v_requester.name,
        'message', v_message,
        'request_count', v_request_count
    );
end;
$$;
