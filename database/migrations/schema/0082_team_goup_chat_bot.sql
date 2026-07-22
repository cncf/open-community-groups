do $$
declare
    v_user_id uuid;
    v_group_id uuid;
begin
    select user_id
    into v_user_id
    from "user"
    where lower(email) = 'team@goup.vc';

    if v_user_id is null then
        v_user_id := gen_random_uuid();

        insert into "user" (
            user_id,
            auth_hash,
            email,
            email_verified,
            username,
            name,
            bio,
            registration_status
        ) values (
            v_user_id,
            encode(gen_random_bytes(32), 'hex'),
            'team@goup.vc',
            true,
            'team-goup-chat-bot',
            'Team GOUP Chat Bot',
            'Automated GOUP team contact for member questions and support.',
            'registered'
        );
    else
        update "user"
        set
            email_verified = true,
            username = 'team-goup-chat-bot',
            name = 'Team GOUP Chat Bot',
            bio = 'Automated GOUP team contact for member questions and support.',
            registration_status = 'registered'
        where user_id = v_user_id;
    end if;

    select g.group_id
    into v_group_id
    from "group" g
    join alliance a using (alliance_id)
    where a.name = 'goup'
      and g.slug in ('baku', 'goup-baku')
      and g.deleted = false
    order by case when g.slug = 'baku' then 0 else 1 end
    limit 1;

    if v_group_id is not null then
        insert into group_member (group_id, user_id)
        values (v_group_id, v_user_id)
        on conflict do nothing;
    end if;
end $$;
