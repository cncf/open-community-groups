-- sync_event_cfs_labels synchronizes an event's CFS labels.
create or replace function sync_event_cfs_labels(
    p_event_id uuid,
    p_cfs_labels jsonb
)
returns void as $$
declare
    v_cfs_label jsonb;
    v_cfs_label_id uuid;
    v_processed_cfs_label_ids uuid[] := '{}';
begin
    -- Upsert labels from the payload
    if p_cfs_labels is not null then
        for v_cfs_label in select jsonb_array_elements(p_cfs_labels)
        loop
            v_cfs_label_id := nullif(v_cfs_label->>'event_cfs_label_id', '')::uuid;

            if v_cfs_label_id is null then
                insert into event_cfs_label (event_id, name, color)
                values (
                    p_event_id,
                    nullif(v_cfs_label->>'name', ''),
                    v_cfs_label->>'color'
                )
                returning event_cfs_label_id into v_cfs_label_id;
            else
                update event_cfs_label set
                    color = v_cfs_label->>'color',
                    name = nullif(v_cfs_label->>'name', '')
                where event_cfs_label_id = v_cfs_label_id
                and event_id = p_event_id;

                if not found then
                    raise exception 'event CFS label % not found for event %', v_cfs_label_id, p_event_id;
                end if;
            end if;

            v_processed_cfs_label_ids := array_append(v_processed_cfs_label_ids, v_cfs_label_id);
        end loop;

        -- Remove labels omitted from the payload
        delete from event_cfs_label
        where event_id = p_event_id
        and not (event_cfs_label_id = any(v_processed_cfs_label_ids));
    else
        -- Remove all labels when the payload omits them
        delete from event_cfs_label where event_id = p_event_id;
    end if;
end;
$$ language plpgsql;
