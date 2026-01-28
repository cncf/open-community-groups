-- Drop functions with old return types so they can be recreated.
drop function if exists search_events(jsonb);
drop function if exists search_groups(jsonb);
