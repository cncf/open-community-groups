-- add_mentorship_request records a mentorship request and returns email metadata.
create or replace function add_mentorship_request(
    p_requester_user_id uuid,
    p_mentor_username text,
    p_input jsonb
) returns jsonb language plpgsql as $$
declare
    v_audience_type text := nullif(trim(p_input->>'audience_type'), '');
    v_message text := nullif(trim(p_input->>'message'), '');
    v_mentor record;
    v_requester record;
    v_request_id uuid;
    v_request_count int;
begin
    if v_audience_type not in ('individual', 'business') then
        raise exception 'invalid mentorship request type';
    end if;

    if v_message is null then
        raise exception 'message is required';
    end if;

    select
        user_id,
        email,
        username,
        name,
        mentorship_businesses,
        mentorship_individuals,
        mentorship_price
    into v_mentor
    from "user"
    where lower(username) = lower(p_mentor_username)
      and email_verified = true
      and registration_status = 'registered';

    if v_mentor.user_id is null then
        raise exception 'mentor not found';
    end if;

    if v_mentor.user_id = p_requester_user_id then
        raise exception 'you cannot request mentorship from yourself';
    end if;

    if v_audience_type = 'individual' and not v_mentor.mentorship_individuals then
        raise exception 'mentor does not accept individual mentorship requests';
    end if;

    if v_audience_type = 'business' and not v_mentor.mentorship_businesses then
        raise exception 'mentor does not accept business mentorship requests';
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

    insert into mentorship_request (
        mentor_user_id,
        requester_user_id,
        audience_type,
        message
    ) values (
        v_mentor.user_id,
        v_requester.user_id,
        v_audience_type,
        v_message
    )
    returning mentorship_request_id into v_request_id;

    select count(*)::int
    into v_request_count
    from mentorship_request
    where mentor_user_id = v_mentor.user_id;

    return jsonb_build_object(
        'mentorship_request_id', v_request_id,
        'mentor_user_id', v_mentor.user_id,
        'mentor_email', v_mentor.email,
        'mentor_username', v_mentor.username,
        'mentor_name', v_mentor.name,
        'mentor_price', v_mentor.mentorship_price,
        'requester_user_id', v_requester.user_id,
        'requester_email', v_requester.email,
        'requester_username', v_requester.username,
        'requester_name', v_requester.name,
        'audience_type', v_audience_type,
        'message', v_message,
        'request_count', v_request_count
    );
end;
$$;
