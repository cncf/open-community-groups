-- Updates whether a group report is visible publicly.
create or replace function update_group_report_public_enabled(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_group_id uuid,
    p_enabled boolean
) returns void as $$
begin
    update "group"
    set report_public_enabled = p_enabled
    where group_id = p_group_id
    and alliance_id = p_alliance_id
    and deleted = false;

    if not found then
        raise exception 'group not found';
    end if;

    perform insert_audit_log(
        case when p_enabled then 'group_report_published' else 'group_report_unpublished' end,
        p_actor_user_id,
        'group',
        p_group_id,
        p_alliance_id,
        p_group_id
    );
end;
$$ language plpgsql;
