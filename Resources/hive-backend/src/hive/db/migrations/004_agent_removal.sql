-- 004: the human can remove an agent from a project (POST /v1/agents/{agent_id}/remove).
-- Removal is a soft delete. Messages, tasks, checkpoints, handoffs and activity keep pointing at the agent row,
-- so history stays readable and attributed. Additive only.
-- No transaction control: db/migrations.py wraps each file in BEGIN IMMEDIATE ... COMMIT.

-- NULL for every active agent. Once set, the agent is hidden from lists and can no longer reconnect.
ALTER TABLE agents ADD COLUMN removed_at TEXT;
