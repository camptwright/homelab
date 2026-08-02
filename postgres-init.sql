-- Runs once on first postgres container start (empty volume only).
-- Passwords are placeholders; SETUP.md step A5 rewrites them from .env
-- immediately after first boot via ALTER USER.
--
-- NOTE: because this only runs on an EMPTY volume, anything added here after
-- the cluster exists must ALSO be applied by hand to the live instance.
-- Wellthread's roles were added that way on 2026-08-02.

CREATE USER adjutant   WITH PASSWORD 'changeme';
CREATE USER dashboard  WITH PASSWORD 'changeme';
CREATE USER miniflux   WITH PASSWORD 'changeme';
CREATE USER wellthread WITH PASSWORD 'changeme';

CREATE DATABASE adjutant   OWNER adjutant;
CREATE DATABASE dashboard  OWNER dashboard;
CREATE DATABASE miniflux   OWNER miniflux;
CREATE DATABASE wellthread OWNER wellthread;

-- ---------------------------------------------------------------- wellthread
-- Self-hosted Supabase contract (GoTrue + PostgREST). PostgREST logs in as
-- `authenticator`, which holds no privileges of its own (NOINHERIT) and
-- SET ROLEs into one of the three below based on the JWT's `role` claim.
-- service_role is BYPASSRLS and is the trusted server-side identity used by
-- the ported edge functions - it must never be reachable from the browser.
CREATE ROLE anon          NOLOGIN NOINHERIT;
CREATE ROLE authenticated NOLOGIN NOINHERIT;
CREATE ROLE service_role  NOLOGIN NOINHERIT BYPASSRLS;
CREATE ROLE authenticator LOGIN NOINHERIT PASSWORD 'changeme';
CREATE ROLE supabase_auth_admin LOGIN CREATEROLE PASSWORD 'changeme';
GRANT anon, authenticated, service_role TO authenticator;

\c adjutant
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\c dashboard
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\c wellthread
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- GoTrue owns and migrates the auth schema (auth.users et al).
CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA auth   TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO authenticated, service_role;
