-- 003: stable project identity.
-- Until now a project was identified only by its folder path (the `project` row is the constant id=1), so an
-- MCP connection could not tell which project an agent meant to join. `uid` ('prj_' + 16 hex) is generated on
-- first open (HiveApp.migrate -> ProjectService.ensure_uid) and never changes unless a copied workspace has
-- to be given its own identity. NULLs are allowed only until that first open.
ALTER TABLE project ADD COLUMN uid TEXT;
CREATE UNIQUE INDEX idx_project_uid ON project(uid);
