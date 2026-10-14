-- Drop the community name lookup replaced by list_community_groups.

drop function if exists get_community_name_by_id(uuid);
