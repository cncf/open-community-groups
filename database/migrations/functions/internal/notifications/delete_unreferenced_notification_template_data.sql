-- Deletes stored notification template data rows that are no longer referenced by any notification.
create or replace function delete_unreferenced_notification_template_data(
    p_template_data_ids uuid[]
)
returns void as $$
begin
    -- Return immediately when no template data ids are supplied
    if p_template_data_ids is null or cardinality(p_template_data_ids) = 0 then
        return;
    end if;

    -- Remove template data rows with no remaining notification references
    delete from notification_template_data ntd
    where ntd.notification_template_data_id = any(p_template_data_ids)
    and not exists (
        select 1
        from notification n
        where n.notification_template_data_id = ntd.notification_template_data_id
    );
end;
$$ language plpgsql;
