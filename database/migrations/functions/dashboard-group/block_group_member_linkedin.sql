-- Blocks a group member's LinkedIn account from future LinkedIn login/signup.
create or replace function block_group_member_linkedin(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_user_id uuid
) returns void as $$
declare
    v_linkedin_subject text;
begin
    select u.provider #>> '{linkedin,subject}'
    into v_linkedin_subject
    from group_member gm
    join "user" u on u.user_id = gm.user_id
    where gm.group_id = p_group_id
      and gm.user_id = p_user_id;

    if not found then
        raise exception 'user is not a group member';
    end if;

    if nullif(trim(v_linkedin_subject), '') is null then
        raise exception 'user does not have a linked LinkedIn account';
    end if;

    insert into linkedin_blocklist (
        linkedin_subject,
        blocked_user_id,
        blocked_by_user_id,
        reason
    )
    values (
        v_linkedin_subject,
        p_user_id,
        p_actor_user_id,
        'Blocked from group member dashboard'
    )
    on conflict (linkedin_subject) do update
    set blocked_user_id = excluded.blocked_user_id,
        blocked_by_user_id = excluded.blocked_by_user_id,
        reason = excluded.reason;

    perform insert_audit_log(
        'linkedin_account_blocked',
        p_actor_user_id,
        'user',
        p_user_id,
        (select alliance_id from "group" where group_id = p_group_id),
        p_group_id
    );
end;
$$ language plpgsql;
