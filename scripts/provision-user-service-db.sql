-- scripts/provision-user-service-db.sql
--
-- Provisions the Tier-3 database and least-privilege role for clickkart-user-service.
-- Run once per environment, as a superuser, passing the generated password in as a variable:
--
--   psql -U postgres -h localhost -v user_db_password="$USER_DB_PASSWORD" \
--        -f scripts/provision-user-service-db.sql
--
-- The password is a psql variable rather than a literal on purpose: this file is committed to a
-- public repository, so it must never contain a working credential. The real value lives only in
-- the gitignored .env locally, and comes from the secrets manager in every real environment.
--
-- Follows the same rule as every other service (see clickkart-config-repository's README): the
-- role owns exactly one database and CONNECT is revoked from PUBLIC, so a leaked credential for
-- one service fails at connect time against another's data, before any query runs.

CREATE ROLE clickkart_user_app WITH LOGIN PASSWORD :'user_db_password';
CREATE DATABASE clickkart_user OWNER clickkart_user_app;

-- No other role may even open a connection to this database.
REVOKE CONNECT ON DATABASE clickkart_user FROM PUBLIC;
GRANT  CONNECT ON DATABASE clickkart_user TO clickkart_user_app;

\connect clickkart_user

-- The role owns the database, so it already owns objects it creates; these grants make that
-- explicit and cover objects created by any other means.
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO clickkart_user_app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO clickkart_user_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES    TO clickkart_user_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO clickkart_user_app;
