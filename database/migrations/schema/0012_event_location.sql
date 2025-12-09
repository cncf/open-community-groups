-- Add location column to event table
alter table event add column location geography(point, 4326);

-- Create spatial index for efficient geographic queries
create index event_location_idx on event using gist (location);
