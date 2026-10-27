-- Adds the pending event purchase hold index.

-- Bound lock waits and the index build so the migration fails instead of
-- stalling the app. Building it apart from 0096 keeps the scan of
-- event_purchase out of that migration's exclusive event lock.
set local lock_timeout = '5s';
set local statement_timeout = '10min';

-- Index pending event purchase holds by deadline for the enrollment worker
-- claim.
create index event_purchase_pending_hold_expires_at_idx
    on event_purchase (hold_expires_at)
    where status = 'pending';
