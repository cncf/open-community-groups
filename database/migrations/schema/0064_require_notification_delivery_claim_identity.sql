-- Requires delivery claim timestamps when finalizing notification claims.

-- Drop the claim function before extending its returned delivery metadata
drop function if exists claim_pending_notification(integer, integer);

-- Drop finalizer signatures that do not require the delivery claim timestamp
drop function if exists mark_notification_delivery_unknown(uuid, text);
drop function if exists requeue_notification(uuid, text, bigint, bigint, integer);
drop function if exists update_notification(uuid, text);
