# little_datamonger

Dockerized PostgreSQL, pgAdmin, and NocoDB for quickly standing up a small database management stack.

## What is included

- PostgreSQL for the actual database storage
- pgAdmin for direct database administration
- NocoDB for a spreadsheet-style interface on top of Postgres

## Requirements

- Docker
- Docker Compose

## Setup

1. Copy [.env.example](.env.example) to [.env](.env).
2. Edit [.env](.env) to set your passwords, database name, and host ports.
3. Start the stack:

```bash
docker compose up -d
```

4. Check the containers:

```bash
docker compose ps
```

## Access

The default ports are configurable through [.env](.env):

- PostgreSQL: `localhost:15432`
- pgAdmin: `http://localhost:5050`
- NocoDB: `http://localhost:8999`

If you change the ports in [.env](.env), the stack will use those values the next time you run Compose.

## Environment variables

The most important variables are:

- `POSTGRES_USER`: database username
- `POSTGRES_PASSWORD`: database password
- `POSTGRES_DB`: default database name
- `PGADMIN_DEFAULT_EMAIL`: pgAdmin login email
- `PGADMIN_DEFAULT_PASSWORD`: pgAdmin login password
- `POSTGRES_HOST_PORT`: host port exposed for PostgreSQL
- `PGADMIN_HOST_PORT`: host port exposed for pgAdmin
- `NOCODB_HOST_PORT`: host port exposed for NocoDB

## Notes

- Secrets should live in [.env](.env), not in the compose file.
- The data lives in Docker volumes, so your database survives container restarts.
- You can stop the stack with `docker compose down`.
- The service images are pinned to known versions so the stack behaves consistently across machines.

## Suggested next step

If you want to upgrade the stack, change the image tags intentionally and test the compose file again before rolling it out.
