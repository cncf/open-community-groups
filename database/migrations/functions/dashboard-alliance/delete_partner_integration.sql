-- Deletes a partner integration owned by an alliance.
create or replace function delete_partner_integration(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_partner_integration_id uuid
)
returns void as $$
begin
    delete from partner_integration
    where alliance_id = p_alliance_id
      and partner_integration_id = p_partner_integration_id;

    if not found then
        raise exception 'partner integration not found';
    end if;

    perform insert_audit_log(
        'partner_integration_deleted', p_actor_user_id, 'partner_integration',
        p_partner_integration_id, p_alliance_id
    );
end;
$$ language plpgsql;
