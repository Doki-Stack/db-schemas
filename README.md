# db-schemas

Language-agnostic SQL migrations for the Doki Stack platform. Contains all database schemas, Row-Level Security (RLS) policies, and seed data used across Go, Rust, and Python services.

## Purpose

This repository is the single source of truth for all PostgreSQL schemas. Migrations are plain SQL files managed by golang-migrate or dbmate. Each service connects to PostgreSQL using its own language-native driver (pgx for Go, sqlx for Rust, psycopg for Python) but the schema is defined here.

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Database | PostgreSQL 16+ |
| Migrations | golang-migrate or dbmate |
| Schema Format | Raw SQL (no ORM dependency) |
| RLS | Row-Level Security policies per table |
| Tenant Key | `org_id` on every table |

## Tables

| Table | Purpose |
|-------|---------|
| `tasks` | User task records |
| `plans` | Generated terraform/ansible plans |
| `approvals` | HITL approval records |
| `audit_logs` | Immutable audit trail |
| `scanner_contexts` | Repository scan results index |
| `policy_rules` | Policy metadata |
| `users` | User records (synced from Auth0) |
| `orgs` | Organization records |
| `agent_memories` | Memory MCP storage (EE) |

## Implementation Phase

**Phase 0** — Foundation. Migrations run before any service starts.

## License

Apache License 2.0 — see [LICENSE](LICENSE)
