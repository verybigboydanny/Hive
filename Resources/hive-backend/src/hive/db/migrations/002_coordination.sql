-- 002: coordination schema (agents extension, sessions, tasks, messages, handoffs,
-- checkpoints, memory, decisions). Additive only: 001 data is preserved.
-- No transaction control: db/migrations.py wraps each file in BEGIN IMMEDIATE ... COMMIT.

-- ------------------------------------------------------------ agents (extend 001)
-- Identity is `agents.id` (internal, unique, never derived from a display name).
-- `name` is a display label only and is NOT unique.
ALTER TABLE agents ADD COLUMN model             TEXT;
ALTER TABLE agents ADD COLUMN role              TEXT;
ALTER TABLE agents ADD COLUMN capabilities      TEXT NOT NULL DEFAULT '[]';
ALTER TABLE agents ADD COLUMN status            TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','idle','blocked','offline'));
ALTER TABLE agents ADD COLUMN status_message    TEXT;
ALTER TABLE agents ADD COLUMN resume_token_hash TEXT;      -- sha256 of secret; NULL for the human

-- One row per MCP connection / API session. An agent identity may have several over time.
CREATE TABLE agent_sessions (
  id                TEXT PRIMARY KEY,                       -- ss_xxxxxxxxxx
  agent_id          TEXT NOT NULL REFERENCES agents(id),
  transport         TEXT NOT NULL DEFAULT 'stdio',
  client_info       TEXT NOT NULL DEFAULT '{}',             -- JSON (client name/version, pid, ...)
  connected_at      TEXT NOT NULL,
  last_seen_at      TEXT NOT NULL,
  disconnected_at   TEXT,
  disconnect_reason TEXT
);
CREATE INDEX idx_sessions_agent ON agent_sessions(agent_id, disconnected_at);

-- ---------------------------------------------------------------------- tasks
CREATE TABLE tasks (
  id               TEXT PRIMARY KEY,                        -- tsk_xxxxxxxxxx
  title            TEXT NOT NULL,
  description      TEXT NOT NULL DEFAULT '',
  status           TEXT NOT NULL DEFAULT 'open'
                   CHECK (status IN ('open','claimed','in_progress','blocked','review','done','cancelled')),
  priority         INTEGER NOT NULL DEFAULT 1 CHECK (priority BETWEEN 0 AND 3),   -- 0 low .. 3 urgent
  labels           TEXT NOT NULL DEFAULT '[]',
  parent_id        TEXT REFERENCES tasks(id),
  created_by       TEXT NOT NULL REFERENCES agents(id),     -- 'user' for the human
  owner_id         TEXT REFERENCES agents(id),
  claim_expires_at TEXT,                                    -- lease end; NULL when unowned/closed
  version          INTEGER NOT NULL DEFAULT 1,              -- optimistic concurrency
  progress_note    TEXT,
  result_summary   TEXT,
  cancel_reason    TEXT,
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL,
  completed_at     TEXT
);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_owner  ON tasks(owner_id, status);

CREATE TABLE task_dependencies (
  task_id       TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  depends_on_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  PRIMARY KEY (task_id, depends_on_id),
  CHECK (task_id <> depends_on_id)
);

-- ------------------------------------------------------------------- messages
CREATE TABLE messages (
  seq           INTEGER PRIMARY KEY AUTOINCREMENT,          -- stable order / cursor
  id            TEXT NOT NULL UNIQUE,                       -- msg_xxxxxxxxxx
  thread_id     TEXT NOT NULL,
  from_agent_id TEXT NOT NULL REFERENCES agents(id),
  to_agent_id   TEXT REFERENCES agents(id),                 -- NULL = broadcast
  kind          TEXT NOT NULL DEFAULT 'message'
                CHECK (kind IN ('message','question','answer','notice','handoff')),
  subject       TEXT,
  body          TEXT NOT NULL,
  task_id       TEXT REFERENCES tasks(id),
  created_at    TEXT NOT NULL
);
CREATE INDEX idx_messages_to     ON messages(to_agent_id, seq);
CREATE INDEX idx_messages_thread ON messages(thread_id, seq);

-- Per-recipient read state (needed for broadcasts). Rows exist only after an explicit mark-read.
CREATE TABLE message_receipts (
  message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  agent_id   TEXT NOT NULL REFERENCES agents(id),
  read_at    TEXT NOT NULL,
  PRIMARY KEY (message_id, agent_id)
);

-- ---------------------------------------------------------------- checkpoints
CREATE TABLE checkpoints (
  id             TEXT PRIMARY KEY,                          -- ckp_xxxxxxxxxx
  agent_id       TEXT NOT NULL REFERENCES agents(id),
  task_id        TEXT REFERENCES tasks(id),
  summary        TEXT NOT NULL,
  state          TEXT NOT NULL DEFAULT '{}',                -- JSON, agent-defined resumable state
  files_modified TEXT NOT NULL DEFAULT '[]',                -- JSON array of workspace paths
  next_action    TEXT,
  created_at     TEXT NOT NULL
);
CREATE INDEX idx_checkpoints_task  ON checkpoints(task_id, created_at);
CREATE INDEX idx_checkpoints_agent ON checkpoints(agent_id, created_at);

-- ------------------------------------------------------------------- handoffs
CREATE TABLE handoffs (
  id             TEXT PRIMARY KEY,                          -- hnd_xxxxxxxxxx
  from_agent_id  TEXT NOT NULL REFERENCES agents(id),
  to_agent_id    TEXT REFERENCES agents(id),                -- NULL = open to any agent
  task_id        TEXT REFERENCES tasks(id),
  checkpoint_id  TEXT REFERENCES checkpoints(id),           -- context snapshot saved with the handoff
  summary        TEXT NOT NULL,
  completed_work TEXT,
  remaining_work TEXT,
  files_modified TEXT NOT NULL DEFAULT '[]',
  next_action    TEXT,
  context        TEXT,
  status         TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','cancelled')),
  accepted_by    TEXT REFERENCES agents(id),
  created_at     TEXT NOT NULL,
  accepted_at    TEXT
);
CREATE INDEX idx_handoffs_status ON handoffs(status, to_agent_id);
CREATE UNIQUE INDEX idx_handoffs_one_pending_per_task
  ON handoffs(task_id) WHERE status = 'pending' AND task_id IS NOT NULL;

-- ----------------------------------------------------- project memory + decisions
CREATE TABLE memory_entries (
  id         TEXT PRIMARY KEY,                              -- mem_xxxxxxxxxx
  key        TEXT NOT NULL UNIQUE,                          -- normalised (lower-case)
  category   TEXT NOT NULL DEFAULT 'general',
  value      TEXT NOT NULL,
  tags       TEXT NOT NULL DEFAULT '[]',
  version    INTEGER NOT NULL DEFAULT 1,
  updated_by TEXT NOT NULL REFERENCES agents(id),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX idx_memory_category ON memory_entries(category);

-- Every version is kept: shared knowledge is never silently lost.
CREATE TABLE memory_history (
  entry_id   TEXT NOT NULL REFERENCES memory_entries(id) ON DELETE CASCADE,
  version    INTEGER NOT NULL,
  value      TEXT NOT NULL,
  updated_by TEXT NOT NULL REFERENCES agents(id),
  updated_at TEXT NOT NULL,
  PRIMARY KEY (entry_id, version)
);

CREATE TABLE decisions (
  id            TEXT PRIMARY KEY,                           -- dec_xxxxxxxxxx
  title         TEXT NOT NULL,
  decision      TEXT NOT NULL,
  rationale     TEXT,
  tags          TEXT NOT NULL DEFAULT '[]',
  status        TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','superseded')),
  supersedes_id TEXT REFERENCES decisions(id),
  decided_by    TEXT NOT NULL REFERENCES agents(id),
  created_at    TEXT NOT NULL
);
CREATE INDEX idx_decisions_status ON decisions(status, created_at);
