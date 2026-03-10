# Non-PostgreSQL Data Stores

This document specifies the configuration for Qdrant, Dragonfly (Redis-compatible), MinIO, and RabbitMQ. While these are not managed by SQL migrations, their schemas are documented here as the single reference for all data store configurations in the platform.

Each store enforces `org_id` tenant isolation through its own mechanism.

---

## Qdrant — Vector Database

### Connection

```
qdrant.data.svc.cluster.local:6333 (gRPC)
qdrant.data.svc.cluster.local:6334 (REST)
```

### Collections

#### `policies` (Phase 1)

Stores embeddings of policy documents for semantic retrieval by the Policy MCP.


| Property        | Value                                       |
| --------------- | ------------------------------------------- |
| Dimensions      | 768                                         |
| Distance        | Cosine                                      |
| Embedding model | nomic-embed-text (via Ollama)               |
| On-disk         | false (dev), true (prod with > 10k vectors) |


**Point structure:**

```json
{
  "id": "<uuid>",
  "vector": [0.1, 0.2, ...],
  "payload": {
    "org_id": "<uuid>",
    "policy_id": "<uuid>",
    "policy_name": "no-public-s3",
    "content": "S3 buckets must not have public ACLs...",
    "effective_date": "2026-01-15T00:00:00Z",
    "severity": "critical"
  }
}
```

**Tenant isolation:** Every query includes a filter:

```json
{
  "filter": {
    "must": [
      { "key": "org_id", "match": { "value": "<org_id>" } }
    ]
  }
}
```

**Fail-closed (ADR-005):** If Qdrant is unavailable or returns an error, the Policy MCP blocks the operation. No fallback to unfiltered queries.

**Collection creation script:**

```bash
curl -X PUT "http://qdrant:6333/collections/policies" \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": { "size": 768, "distance": "Cosine" },
    "payload_schema": {
      "org_id": { "data_type": "Keyword", "points": 0, "is_tenant": true },
      "policy_id": { "data_type": "Keyword" },
      "effective_date": { "data_type": "Datetime" },
      "severity": { "data_type": "Keyword" }
    }
  }'
```

#### `agent_memories` (Phase 3 — EE)

Stores embeddings of agent memories for semantic recall by the Memory MCP.


| Property        | Value                         |
| --------------- | ----------------------------- |
| Dimensions      | 768                           |
| Distance        | Cosine                        |
| Embedding model | nomic-embed-text (via Ollama) |


**Point structure:**

```json
{
  "id": "<uuid>",
  "vector": [0.1, 0.2, ...],
  "payload": {
    "org_id": "<uuid>",
    "memory_type": "preference",
    "key": "terraform-provider-version",
    "relevance_score": 0.95,
    "created_at": "2026-03-01T12:00:00Z"
  }
}
```

**Tenant isolation:** Same `org_id` filter pattern as `policies`.

**Collection creation script:**

```bash
curl -X PUT "http://qdrant:6333/collections/agent_memories" \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": { "size": 768, "distance": "Cosine" },
    "payload_schema": {
      "org_id": { "data_type": "Keyword", "points": 0, "is_tenant": true },
      "memory_type": { "data_type": "Keyword" },
      "key": { "data_type": "Keyword" },
      "relevance_score": { "data_type": "Float" },
      "created_at": { "data_type": "Datetime" }
    }
  }'
```

---

## Dragonfly — Cache (Redis-Compatible)

### Connection

```
dragonfly.data.svc.cluster.local:6379
```

Dev configuration: `--proactor_threads=2` to stay under 2GB RAM (ADR-009).

### Key Format Convention

All keys follow the pattern:

```
{domain}:{org_id}:{identifier}
```

The `org_id` is always present in tenant-scoped keys to prevent cross-tenant cache access.

### Key Patterns

#### Scanner MCP


| Key                                 | TTL | Type             | Purpose                                            |
| ----------------------------------- | --- | ---------------- | -------------------------------------------------- |
| `scan:{org_id}:{repo}:{commit_sha}` | 24h | String (JSON)    | Cached scan result metadata                        |
| `scan:rate:{org_id}:{repo}`         | 5m  | String (counter) | Rate limit: 1 scan per repo per 5 minutes          |
| `scan:concurrent:{org_id}`          | —   | String (counter) | Concurrency limit: max 10 concurrent scans per org |


**Rate limiting logic:**

```
INCR scan:rate:{org_id}:{repo}
if result > 1 → reject (already scanning)
EXPIRE scan:rate:{org_id}:{repo} 300

INCR scan:concurrent:{org_id}
if result > 10 → DECR and reject
# On completion: DECR scan:concurrent:{org_id}
```

#### Execution MCP


| Key                                   | TTL | Type             | Purpose                                             |
| ------------------------------------- | --- | ---------------- | --------------------------------------------------- |
| `exec:idempotency:{org_id}:{plan_id}` | 30m | String           | Idempotency guard: prevent duplicate plan applies   |
| `exec:concurrent:{org_id}`            | —   | String (counter) | Concurrency limit: max 5 concurrent applies per org |


#### Policy MCP


| Key                            | TTL | Type          | Purpose                         |
| ------------------------------ | --- | ------------- | ------------------------------- |
| `policy:{org_id}:{query_hash}` | 24h | String (JSON) | Cached policy evaluation result |


`query_hash` is a SHA-256 of the normalized policy query parameters.

#### API Server


| Key                                | TTL | Type             | Purpose                                      |
| ---------------------------------- | --- | ---------------- | -------------------------------------------- |
| `api:ratelimit:{org_id}:{user_id}` | 1m  | String (counter) | Rate limit: 100 requests per minute per user |


**Rate limiting logic (sliding window):**

```
key = api:ratelimit:{org_id}:{user_id}
INCR key
if result == 1 → EXPIRE key 60
if result > 100 → reject with 429
```

#### Memory MCP (EE — Phase 3)


| Key                           | TTL | Type          | Purpose                                    |
| ----------------------------- | --- | ------------- | ------------------------------------------ |
| `memory:{org_id}:{memory_id}` | 6h  | String (JSON) | Hot cache for frequently recalled memories |


### Cache Invalidation


| Event               | Keys to Invalidate                                       |
| ------------------- | -------------------------------------------------------- |
| New scan completed  | `scan:{org_id}:{repo}:*` (DEL the old commit's cache)    |
| Policy rule updated | `policy:{org_id}:*` (DEL all cached evaluations for org) |
| Memory updated      | `memory:{org_id}:{memory_id}` (DEL specific memory)      |
| Plan status changed | No cache invalidation (plans are not cached)             |


### Monitoring

Key metrics to track:

- `dragonfly_used_memory_bytes` — alert at 80% of limit
- `dragonfly_connected_clients` — connection pool sizing
- `dragonfly_keyspace_hits` / `dragonfly_keyspace_misses` — cache hit ratio
- Key count by prefix — `SCAN` with pattern to count per-domain keys

---

## MinIO — Object Storage

### Connection

```
minio.data.svc.cluster.local:9000 (API)
minio.data.svc.cluster.local:9001 (Console — dev only)
```

### Buckets

All buckets are created during Phase 0 with versioning enabled.


| Bucket              | Purpose                                       | Versioning | Phase |
| ------------------- | --------------------------------------------- | ---------- | ----- |
| `scanner-artifacts` | Scan output files (skill.md, instructions.md) | Enabled    | 0     |
| `terraform-states`  | Terraform state snapshots before apply        | Enabled    | 0     |
| `execution-plans`   | Generated Terraform/Ansible plans             | Enabled    | 0     |
| `prompts`           | System prompt templates                       | Enabled    | 0     |


### Object Path Conventions

All tenant-scoped objects use the prefix `org_id={org_id}/`:

#### Scanner Artifacts

```
scanner-artifacts/
  org_id={org_id}/
    {repo_name}/
      {commit_sha}/
        skill.md
        instructions.md
```

Example:

```
scanner-artifacts/org_id=a0000000-0000-0000-0000-000000000001/acme-infra/abc123def456/skill.md
```

#### Terraform States

```
terraform-states/
  org_id={org_id}/
    states/
      {workspace}/
        snapshot-{timestamp}.tfstate
```

Example:

```
terraform-states/org_id=a0000000-0000-0000-0000-000000000001/states/production/snapshot-2026-03-10T14:30:00Z.tfstate
```

#### Execution Plans

```
execution-plans/
  org_id={org_id}/
    plans/
      {plan_id}/
        plan.json
```

Example:

```
execution-plans/org_id=a0000000-0000-0000-0000-000000000001/plans/a3000000-0000-0000-0000-000000000001/plan.json
```

#### System Prompts

```
prompts/
  automation/
    v{version}/
      system.md
  review/
    v{version}/
      system.md
```

Prompts are not org-scoped — they are platform-level resources.

### Lifecycle Policies


| Bucket              | Policy                                                                      |
| ------------------- | --------------------------------------------------------------------------- |
| `scanner-artifacts` | Delete objects older than 90 days (configurable per org in EE)              |
| `terraform-states`  | Keep all versions (state is critical); archive to cold storage after 1 year |
| `execution-plans`   | Delete objects older than 30 days (plan metadata lives in PG)               |
| `prompts`           | No expiry — versioned for rollback                                          |


### Tenant Isolation

MinIO does not have built-in RLS. Isolation is enforced at the application layer:

1. Services construct object paths using `org_id` from the validated JWT
2. MinIO bucket policies restrict access to the service account only
3. No direct client access to MinIO — all access is proxied through services
4. Audit logs record every object read/write with org_id

### Bucket Creation Script

```bash
mc alias set doki http://minio.data.svc.cluster.local:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

mc mb doki/scanner-artifacts --ignore-existing
mc mb doki/terraform-states --ignore-existing
mc mb doki/execution-plans --ignore-existing
mc mb doki/prompts --ignore-existing

mc version enable doki/scanner-artifacts
mc version enable doki/terraform-states
mc version enable doki/execution-plans
mc version enable doki/prompts
```

---

## RabbitMQ — Message Queue

### Connection

```
rabbitmq.data.svc.cluster.local:5672 (AMQP)
rabbitmq.data.svc.cluster.local:15672 (Management UI — dev only)
```

Image: `rabbitmq:4-management` (official, not Bitnami — ADR-006).

### Topology

#### Exchanges


| Exchange           | Type   | Durable | Purpose                                  |
| ------------------ | ------ | ------- | ---------------------------------------- |
| `agent.events`     | topic  | yes     | Agent state updates for SSE fan-out      |
| `scanner.webhooks` | direct | yes     | Webhook ingestion for repo scan triggers |


#### Queues


| Queue                      | Exchange           | Binding Key | Consumer    | DLQ                            |
| -------------------------- | ------------------ | ----------- | ----------- | ------------------------------ |
| `agent.events.api`         | `agent.events`     | `#`         | api-server  | `agent.events.api.dlq`         |
| `scanner.webhooks.scanner` | `scanner.webhooks` | `scan`      | mcp-scanner | `scanner.webhooks.scanner.dlq` |


#### Dead Letter Queues

Every queue has a corresponding DLQ. Messages that fail processing after max retries are routed to the DLQ.


| DLQ                            | Source Queue               | Retention |
| ------------------------------ | -------------------------- | --------- |
| `agent.events.api.dlq`         | `agent.events.api`         | 7 days    |
| `scanner.webhooks.scanner.dlq` | `scanner.webhooks.scanner` | 7 days    |


#### EE Queues (Phase 4)


| Queue                        | Exchange       | Binding Key | Consumer         |
| ---------------------------- | -------------- | ----------- | ---------------- |
| `agent.events.notifications` | `agent.events` | `#`         | ee-notifications |


### Routing Key Format

```
{org_id}.{thread_id}
```

Example: `a0000000-0000-0000-0000-000000000001.550e8400-e29b-41d4-a716-446655440000`

The api-server consumes all messages (`#` binding) and fans out to SSE connections by matching `task_id` from the message payload.

### Consumer Configuration


| Consumer         | Prefetch | Max Retries | Retry Delay               |
| ---------------- | -------- | ----------- | ------------------------- |
| api-server       | 10       | 3           | 1s, 5s, 30s (exponential) |
| mcp-scanner      | 5        | 3           | 5s, 30s, 300s             |
| ee-notifications | 10       | 5           | 1s, 5s, 30s, 300s, 3600s  |


### Message Schema

#### agent.events

```json
{
  "event_type": "plan_created",
  "org_id": "<uuid>",
  "thread_id": "<uuid>",
  "task_id": "<uuid>",
  "timestamp": "2026-03-10T14:30:00Z",
  "payload": {
    "plan_id": "<uuid>",
    "status": "pending_approval",
    "resource_count": 3
  }
}
```

Event types: `task_started`, `plan_created`, `approval_needed`, `approval_decided`, `apply_started`, `apply_succeeded`, `apply_failed`, `rollback_triggered`, `task_completed`, `task_failed`.

#### scanner.webhooks

```json
{
  "source": "github",
  "event": "push",
  "repo": "https://github.com/acme/infra",
  "branch": "main",
  "commit_sha": "abc123def456",
  "org_id": "<uuid>"
}
```

### Topology Setup Script

```bash
# Using rabbitmqadmin (available in management image)
rabbitmqadmin declare exchange name=agent.events type=topic durable=true
rabbitmqadmin declare exchange name=scanner.webhooks type=direct durable=true

rabbitmqadmin declare queue name=agent.events.api durable=true \
  arguments='{"x-dead-letter-exchange": "", "x-dead-letter-routing-key": "agent.events.api.dlq"}'
rabbitmqadmin declare queue name=agent.events.api.dlq durable=true \
  arguments='{"x-message-ttl": 604800000}'

rabbitmqadmin declare queue name=scanner.webhooks.scanner durable=true \
  arguments='{"x-dead-letter-exchange": "", "x-dead-letter-routing-key": "scanner.webhooks.scanner.dlq"}'
rabbitmqadmin declare queue name=scanner.webhooks.scanner.dlq durable=true \
  arguments='{"x-message-ttl": 604800000}'

rabbitmqadmin declare binding source=agent.events destination=agent.events.api routing_key="#"
rabbitmqadmin declare binding source=scanner.webhooks destination=scanner.webhooks.scanner routing_key="scan"
```

---

## Summary — Tenant Isolation by Store


| Store      | Isolation Mechanism                          | Fail Mode                                                |
| ---------- | -------------------------------------------- | -------------------------------------------------------- |
| PostgreSQL | RLS on `org_id` column                       | Fail closed (returns no rows)                            |
| Qdrant     | `org_id` metadata filter on every query      | Fail closed (ADR-005: block if unavailable)              |
| Dragonfly  | `org_id` embedded in key pattern             | Fail open (cache miss falls through to PG/Qdrant)        |
| MinIO      | `org_id=` prefix in object paths             | Fail closed (service constructs path from validated JWT) |
| RabbitMQ   | `org_id` in routing key and message ~payload | N/A (messages are consumed by trusted services only)     |
| Vault      | Path: `secret/data/orgs/{org_id}/...`        | Fail closed (no secret = no operation)                   |


