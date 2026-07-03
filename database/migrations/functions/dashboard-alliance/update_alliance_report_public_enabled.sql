-- Updates whether an alliance report is visible publicly.
create or replace function update_alliance_report_public_enabled(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_enabled boolean
) returns void as $$
begin
    update alliance
    set report_public_enabled = p_enabled
    where alliance_id = p_alliance_id;

    if not found then
        raise exception 'alliance not found';
    end if;

    perform insert_audit_log(
        case when p_enabled then 'alliance_report_published' else 'alliance_report_unpublished' end,
        p_actor_user_id,
        'alliance',
        p_alliance_id,
        p_alliance_id
    );
end;
$$ language plpgsql;
