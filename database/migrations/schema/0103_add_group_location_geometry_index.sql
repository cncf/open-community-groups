-- Adds the planar group location index.

-- Bound lock waits and the index build so the migration fails instead of
-- stalling the app. The build blocks group writes until this migration
-- commits.
set local lock_timeout = '5s';
set local statement_timeout = '10min';

-- Index the planar group location for the explore groups bbox test.
create index group_location_geometry_idx on "group" using gist ((location::geometry));

-- Collect statistics for the new group location expression index.
analyze "group";
