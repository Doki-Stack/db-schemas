# Row-Level Security and Multi-Tenancy

## Overview

Every table in the Doki Stack platform that contains tenant data is protected by PostgreSQL Row-Level Security (RLS). The tenant key is `org_id` (UUID), propagated through every layer:

```
JWT (Auth0) → Kong (X-Org-Id header) → Service middleware → SET app.current_org_id → RLS policy
```

RLS is the last line of defense. Even if application code has a bug that omits an `org_id` filter, the database itself prevents cross-tenant data access.

## Database Roles

Two PostgreSQL roles are used to enforce separation of concerns:

### `app_service` — Application Role

Used by all services at runtime. RLS applies.

```sql
CREATE ROLE app_service LOGIN PASSWORD '...' ;
GRANT CONNECT ON DATABASE ai_automation TO app_service;
GRANT USAGE ON SCHEMA public TO app_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_service;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE ON SEQUENCES TO app_service;
```

### `app_admin` — Migration/Admin Role

Used only for running migrations and admin tasks. Bypasses RLS (table owner).

```sql
CREATE ROLE app_admin LOGIN PASSWORD '...' CREATEDB;
GRANT ALL ON DATABASE ai_automation TO app_admin;
```

Tables are owned by `app_admin`. Since RLS applies to non-owner roles by default, `app_service` is always subject to RLS without needing `FORCE ROW LEVEL SECURITY`. However, we use `FORCE` as defense-in-depth to also apply RLS to the table owner if a connection accidentally uses `app_admin`.

## RLS Policy Pattern

### Standard Tenant Isolation Policy

Applied to every tenant-scoped table via Migration 012:

```sql
-- Template applied to: users, tasks, plans, approvals, scanner_contexts,
-- policy_rules, cost_limits
ALTER TABLE {table} ENABLE ROW LEVEL SECURITY;
ALTER TABLE {table} FORCE ROW LEVEL SECURITY;

CREATE POLICY {table}_org_isolation ON {table}
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);
```

The `USING` clause restricts SELECT, UPDATE, DELETE. The `WITH CHECK` clause restricts INSERT and UPDATE (ensures new/modified rows match the current org).

The second parameter `true` in `current_setting('app.current_org_id', true)` returns NULL instead of raising an error if the setting is not set. This means queries will return no rows rather than erroring — fail closed.

### Audit Log Policy

`audit_logs` uses a special policy: services can INSERT audit records (the `WITH CHECK` verifies org_id), but SELECT is restricted to the current org. No UPDATE or DELETE is permitted.

```sql
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs FORCE ROW LEVEL SECURITY;

CREATE POLICY audit_logs_insert ON audit_logs
  FOR INSERT
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

CREATE POLICY audit_logs_select ON audit_logs
  FOR SELECT
  USING (org_id = current_setting('app.current_org_id', true)::uuid);

-- No UPDATE or DELETE policies — audit logs are immutable
```

### Tables Exempt from RLS

| Table | Reason |
|-------|--------|
| `orgs` | Top-level entity. Has no parent org_id. Access is controlled at the application layer by matching the org_id from the JWT. |

## Connection Setup

Every service must set `app.current_org_id` on its database connection before executing any query. This is done per-connection (or per-transaction for connection poolers in transaction mode).

### Go (pgx)

```go
func withOrgID(ctx context.Context, pool *pgxpool.Pool, orgID uuid.UUID) (*pgxpool.Conn, error) {
    conn, err := pool.Acquire(ctx)
    if err != nil {
        return nil, err
    }
    _, err = conn.Exec(ctx, "SET app.current_org_id = $1", orgID.String())
    if err != nil {
        conn.Release()
        return nil, err
    }
    return conn, nil
}
```

### Rust (sqlx)

```rust
async fn with_org_id(pool: &PgPool, org_id: Uuid) -> Result<PgConnection> {
    let mut conn = pool.acquire().await?;
    sqlx::query("SET app.current_org_id = $1")
        .bind(org_id.to_string())
        .execute(&mut *conn)
        .await?;
    Ok(conn)
}
```

### Python (psycopg)

```python
async def with_org_id(pool: AsyncConnectionPool, org_id: str) -> AsyncConnection:
    conn = await pool.getconn()
    await conn.execute("SET app.current_org_id = %s", (org_id,))
    return conn
```

## Connection Pooling Considerations

### PgBouncer (Transaction Mode)

When using PgBouncer in transaction mode, `SET` commands are reset when the connection is returned to the pool. This is the desired behavior — each transaction gets a fresh connection with no residual `org_id`.

If PgBouncer is used in session mode, connections persist settings between transactions. This is **not recommended** for multi-tenant workloads.

### In-Application Pooling

Go (pgx) and Rust (sqlx) use in-application connection pools. The `SET` must be issued after acquiring the connection and before any queries. The setting persists for the lifetime of the connection checkout.

## Full Migration 012: Enable RLS

```sql
-- migrate:up

-- Users
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;
CREATE POLICY users_org_isolation ON users
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Tasks
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks FORCE ROW LEVEL SECURITY;
CREATE POLICY tasks_org_isolation ON tasks
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Plans
ALTER TABLE plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE plans FORCE ROW LEVEL SECURITY;
CREATE POLICY plans_org_isolation ON plans
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Approvals
ALTER TABLE approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE approvals FORCE ROW LEVEL SECURITY;
CREATE POLICY approvals_org_isolation ON approvals
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Audit Logs (special: INSERT + SELECT only, no UPDATE/DELETE)
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs FORCE ROW LEVEL SECURITY;
CREATE POLICY audit_logs_insert ON audit_logs
  FOR INSERT
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);
CREATE POLICY audit_logs_select ON audit_logs
  FOR SELECT
  USING (org_id = current_setting('app.current_org_id', true)::uuid);

-- Scanner Contexts
ALTER TABLE scanner_contexts ENABLE ROW LEVEL SECURITY;
ALTER TABLE scanner_contexts FORCE ROW LEVEL SECURITY;
CREATE POLICY scanner_contexts_org_isolation ON scanner_contexts
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Policy Rules
ALTER TABLE policy_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_rules FORCE ROW LEVEL SECURITY;
CREATE POLICY policy_rules_org_isolation ON policy_rules
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Cost Limits
ALTER TABLE cost_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE cost_limits FORCE ROW LEVEL SECURITY;
CREATE POLICY cost_limits_org_isolation ON cost_limits
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- migrate:down

DROP POLICY IF EXISTS cost_limits_org_isolation ON cost_limits;
ALTER TABLE cost_limits DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS policy_rules_org_isolation ON policy_rules;
ALTER TABLE policy_rules DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS scanner_contexts_org_isolation ON scanner_contexts;
ALTER TABLE scanner_contexts DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS audit_logs_select ON audit_logs;
DROP POLICY IF EXISTS audit_logs_insert ON audit_logs;
ALTER TABLE audit_logs DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS approvals_org_isolation ON approvals;
ALTER TABLE approvals DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS plans_org_isolation ON plans;
ALTER TABLE plans DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tasks_org_isolation ON tasks;
ALTER TABLE tasks DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS users_org_isolation ON users;
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
```

## RLS Validation Strategy

A validation script (`scripts/validate-rls.sh`) verifies that RLS works as expected. It runs as part of CI.

### Validation Steps

1. Connect as `app_admin`, create two test orgs (org_a, org_b)
2. Insert test data into every tenant-scoped table for both orgs
3. Connect as `app_service`, set `app.current_org_id = org_a`
4. Query each table — assert only org_a rows are returned
5. Attempt to INSERT a row with `org_id = org_b` — assert it fails
6. Attempt to UPDATE a row to `org_id = org_b` — assert it fails
7. Set `app.current_org_id = org_b`, repeat assertions for org_b
8. Verify audit_logs: INSERT allowed, UPDATE blocked, DELETE blocked
9. Verify orgs table: accessible without org_id filter (no RLS)
10. Clean up test data

### Edge Cases to Validate

- **Missing `app.current_org_id`:** queries should return zero rows (not error), because `current_setting(..., true)` returns NULL on missing setting, and `org_id = NULL` is always false.
- **Invalid UUID format:** should return zero rows (cast fails to NULL with `true` parameter).
- **Partitioned table (audit_logs):** RLS must apply across all partitions.

## org_id Propagation — Full Path

```
┌─────────────┐    ┌──────────┐    ┌───────────────┐    ┌──────────────┐    ┌────────────┐
│   Browser   │───►│  Auth0   │───►│  Kong Gateway │───►│   Service    │───►│ PostgreSQL │
│ (Next.js)   │    │  (JWT)   │    │ (X-Org-Id)    │    │ (middleware) │    │   (RLS)    │
└─────────────┘    └──────────┘    └───────────────┘    └──────────────┘    └────────────┘
                        │                  │                    │                  │
                   org_id in          Extracts from        Validates         SET app.
                   JWT claims         JWT, injects         X-Org-Id,       current_org_id
                                     X-Org-Id header      rejects if
                                                          missing
```

1. **Auth0:** User authenticates. JWT contains `org_id` in custom claims.
2. **Kong:** Plugin extracts `org_id` from JWT, injects `X-Org-Id` header into upstream request.
3. **Service middleware:** Extracts `X-Org-Id` header. Rejects request with 400 if missing. Validates UUID format.
4. **Database connection:** Service calls `SET app.current_org_id = '{org_id}'` before any query.
5. **RLS policy:** PostgreSQL filters all reads/writes to the current org.

## Multi-Tenancy Beyond PostgreSQL

While this document focuses on PostgreSQL RLS, `org_id` scoping applies to all data stores:

| Store | Scoping Mechanism |
|-------|-------------------|
| PostgreSQL | RLS on `org_id` |
| MinIO | Object path prefix: `org_id={org_id}/...` |
| Qdrant | Metadata filter: `org_id` field on every point |
| Dragonfly | Key prefix: `{org_id}:{domain}:{identifier}` |
| Vault | Path: `secret/data/orgs/{org_id}/...` |
| RabbitMQ | Routing key prefix: `{org_id}.{thread_id}` |

See `06-non-pg-data-stores.md` for details on non-PostgreSQL data stores.
