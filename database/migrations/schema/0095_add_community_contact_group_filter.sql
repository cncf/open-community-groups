-- Drops community_contact_filter_values so it can be recreated returning the selected group identifiers.

drop function if exists community_contact_filter_values(jsonb);
