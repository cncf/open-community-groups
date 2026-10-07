-- Validates the labels payload of an event.
create or replace function validate_event_labels_payload(p_labels jsonb)
returns void as $$
begin
    -- Require an array of labels
    if p_labels is null or jsonb_typeof(p_labels) <> 'array' then
        raise exception 'invalid label payload' using errcode = 'OCG01';
    end if;

    -- Enforce the maximum number of labels accepted in one payload
    if jsonb_array_length(p_labels) > 200 then
        raise exception 'too many labels' using errcode = 'OCG01';
    end if;

    -- Require an identifier and a non-blank name for every label
    if exists (
        select 1
        from jsonb_array_elements(p_labels) as label
        where jsonb_typeof(label) <> 'object'
        or nullif(btrim(label->>'event_label_id'), '') is null
        or nullif(btrim(label->>'name'), '') is null
    ) then
        raise exception 'invalid label payload' using errcode = 'OCG01';
    end if;

    -- Reject duplicate label names within the payload
    if exists (
        select 1
        from jsonb_array_elements(p_labels) as label
        group by btrim(label->>'name')
        having count(*) > 1
    ) then
        raise exception 'duplicate label names' using errcode = 'OCG01';
    end if;

    -- Reject duplicate label identifiers within the payload
    if exists (
        select 1
        from jsonb_array_elements(p_labels) as label
        group by (label->>'event_label_id')::uuid
        having count(*) > 1
    ) then
        raise exception 'duplicate label ids' using errcode = 'OCG01';
    end if;
end;
$$ language plpgsql;
