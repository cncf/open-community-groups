-- add_intentional_dating_intro records an admin-curated private introduction.
create or replace function add_intentional_dating_intro(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_group_id uuid,
    p_first_user_id uuid,
    p_second_user_id uuid,
    p_admin_notes text default null
)
returns uuid as $$
declare
    v_intro_id uuid;
begin
    if p_first_user_id = p_second_user_id then
        raise exception 'introduction requires two different users';
    end if;

    if not exists (
        select 1
        from alliance a
        join "group" g on g.alliance_id = a.alliance_id
        where a.alliance_id = p_alliance_id
          and a.active = true
          and a.intentional_dating_enabled = true
          and g.group_id = p_group_id
          and g.active = true
          and g.deleted = false
          and g.intentional_dating_enabled = true
    ) then
        raise exception 'intentional dating is not enabled for this group';
    end if;

    if not exists (
        select 1
        from group_member gm
        join "user" u on u.user_id = gm.user_id
        where gm.group_id = p_group_id
          and gm.user_id = p_first_user_id
          and u.email_verified = true
          and u.registration_status = 'registered'
          and u.intentional_dating_enabled = true
    ) or not exists (
        select 1
        from group_member gm
        join "user" u on u.user_id = gm.user_id
        where gm.group_id = p_group_id
          and gm.user_id = p_second_user_id
          and u.email_verified = true
          and u.registration_status = 'registered'
          and u.intentional_dating_enabled = true
    ) then
        raise exception 'both users must be opted-in group members';
    end if;

    insert into intentional_dating_intro (
        alliance_id,
        group_id,
        introduced_by_user_id,
        first_user_id,
        second_user_id,
        admin_notes
    ) values (
        p_alliance_id,
        p_group_id,
        p_actor_user_id,
        p_first_user_id,
        p_second_user_id,
        nullif(p_admin_notes, '')
    )
    returning intentional_dating_intro_id into v_intro_id;

    perform insert_audit_log(
        'intentional_dating_intro_added',
        p_actor_user_id,
        'intentional_dating_intro',
        v_intro_id,
        p_alliance_id,
        p_group_id
    );

    return v_intro_id;
end;
$$ language plpgsql;
