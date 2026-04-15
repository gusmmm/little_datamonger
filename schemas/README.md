# Contents of this folder

This folder contains the schemas to create a full fledged postgresql

## Schema conventions

- Every application table should include:
	- `created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`
	- `last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP`
- The schema script defines a shared trigger function that updates `last_updated` on every row update.
- Trigger creation is automated for all `public` base tables that have a `last_updated` column, so new tables follow the same behavior as soon as the schema script is run.
