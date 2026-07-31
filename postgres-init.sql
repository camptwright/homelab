-- Runs once on first postgres container start (empty volume only).
-- Passwords are placeholders; SETUP.md step A5 rewrites them from .env
-- immediately after first boot via ALTER USER.

CREATE USER adjutant  WITH PASSWORD 'changeme';
CREATE USER dashboard WITH PASSWORD 'changeme';
CREATE USER miniflux  WITH PASSWORD 'changeme';

CREATE DATABASE adjutant  OWNER adjutant;
CREATE DATABASE dashboard OWNER dashboard;
CREATE DATABASE miniflux  OWNER miniflux;

\c adjutant
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\c dashboard
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
