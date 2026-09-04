-- Converts a JSONB text array into a SQL text array.
create or replace function jsonb_text_array(p_value jsonb)
returns text[] as $$
    select case
        when p_value is null or jsonb_typeof(p_value) = 'null' then null
        else array(select jsonb_array_elements_text(p_value))
    end;
$$ language sql immutable;
