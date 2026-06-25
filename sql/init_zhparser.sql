-- =============================================================================
-- MCdesk zhparser extension initialization
-- =============================================================================
-- The MCdesk backend uses the zhparser PostgreSQL extension for Chinese
-- full-text search (Flyway migration V1.0.25__Create_Cmdb_Vector_Index.sql).
-- This script must be executed by a PostgreSQL superuser before the backend
-- starts for the first time so that the parser is available to Flyway.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS zhparser;
