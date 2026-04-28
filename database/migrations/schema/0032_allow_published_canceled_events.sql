-- Allow canceled events to remain publicly addressable.

alter table event
    drop constraint if exists event_check1;
