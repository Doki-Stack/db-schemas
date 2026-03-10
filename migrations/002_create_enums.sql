-- migrate:up
CREATE TYPE user_role AS ENUM (
  'viewer',
  'operator',
  'approver',
  'admin',
  'platform_owner'
);

CREATE TYPE task_status AS ENUM (
  'pending',
  'running',
  'completed',
  'failed',
  'cancelled'
);

CREATE TYPE plan_type AS ENUM (
  'terraform',
  'ansible'
);

CREATE TYPE plan_status AS ENUM (
  'draft',
  'pending_approval',
  'approved',
  'rejected',
  'expired',
  'applied',
  'failed'
);

CREATE TYPE approval_status AS ENUM (
  'pending',
  'approved',
  'rejected',
  'expired'
);

CREATE TYPE actor_type AS ENUM (
  'user',
  'agent',
  'system'
);

CREATE TYPE severity_level AS ENUM (
  'low',
  'medium',
  'high',
  'critical'
);

CREATE TYPE budget_period AS ENUM (
  'daily',
  'weekly',
  'monthly'
);

-- migrate:down
DROP TYPE IF EXISTS budget_period CASCADE;
DROP TYPE IF EXISTS severity_level CASCADE;
DROP TYPE IF EXISTS actor_type CASCADE;
DROP TYPE IF EXISTS approval_status CASCADE;
DROP TYPE IF EXISTS plan_status CASCADE;
DROP TYPE IF EXISTS plan_type CASCADE;
DROP TYPE IF EXISTS task_status CASCADE;
DROP TYPE IF EXISTS user_role CASCADE;
