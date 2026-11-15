-- RECONSTRUCTED 001: the original file was overwritten by accident.
-- Contains ONLY what surviving original code demonstrably requires:
--   workspace.py  -> project(id,name,created_at), agents(id,agent_key,name,client,kind,
--                    registered_at,last_seen_at) incl. the human row id='user'
--   activity.py   -> activity(id,ts,agent_id,action,target_type,target_id,summary,details)
-- Everything else lives in 002+. db/migrations.py wraps each file in BEGIN IMMEDIATE/COMMIT
-- and records the version in schema_migrations, so no transaction control here.

CREATE TABLE project (
  id         INTEGER PRIMARY KEY CHECK (id = 1),   -- single-row table (INSERT OR IGNORE ... VALUES(1,..))
  name       TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE agents (
  id            TEXT PRIMARY KEY,                  -- 'user' for the human; ag_xxxxxxxxxx for agents
  agent_key     TEXT NOT NULL UNIQUE,              -- stable identity key, e.g. 'human:user'
  name          TEXT NOT NULL,
  client        TEXT NOT NULL,                     -- 'human' | 'claude' | 'gpt' | 'gemini' | ...
  kind          TEXT NOT NULL DEFAULT 'agent' CHECK (kind IN ('agent','human')),
  registered_at TEXT NOT NULL,
  last_seen_at  TEXT NOT NULL
);

CREATE TABLE activity (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,   -- monotonic cursor for polling
  ts          TEXT NOT NULL,
  agent_id    TEXT REFERENCES agents(id),          -- NULL allowed for system events
  action      TEXT NOT NULL,
  target_type TEXT,
  target_id   TEXT,
  summary     TEXT NOT NULL,
  details     TEXT NOT NULL DEFAULT '{}'           -- JSON object text
);
CREATE INDEX idx_activity_agent  ON activity(agent_id, id);
CREATE INDEX idx_activity_action ON activity(action);
