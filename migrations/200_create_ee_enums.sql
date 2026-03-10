-- migrate:up
CREATE TYPE ee.mcp_auth_type AS ENUM (
  'none',
  'api_key',
  'oauth2',
  'mtls'
);

CREATE TYPE ee.mcp_health_status AS ENUM (
  'healthy',
  'degraded',
  'unhealthy',
  'unknown'
);

CREATE TYPE ee.channel_type AS ENUM (
  'slack',
  'teams',
  'pagerduty',
  'email'
);

CREATE TYPE ee.risk_level AS ENUM (
  'low',
  'medium',
  'high',
  'critical'
);

CREATE TYPE ee.report_type AS ENUM (
  'compliance',
  'audit',
  'cost',
  'usage'
);

CREATE TYPE ee.report_format AS ENUM (
  'pdf',
  'csv',
  'json'
);

CREATE TYPE ee.schedule_frequency AS ENUM (
  'daily',
  'weekly',
  'monthly',
  'quarterly'
);

CREATE TYPE ee.license_tier AS ENUM (
  'team',
  'enterprise'
);

CREATE TYPE ee.license_status AS ENUM (
  'active',
  'expired',
  'suspended',
  'trial'
);

-- migrate:down
DROP TYPE IF EXISTS ee.license_status CASCADE;
DROP TYPE IF EXISTS ee.license_tier CASCADE;
DROP TYPE IF EXISTS ee.schedule_frequency CASCADE;
DROP TYPE IF EXISTS ee.report_format CASCADE;
DROP TYPE IF EXISTS ee.report_type CASCADE;
DROP TYPE IF EXISTS ee.risk_level CASCADE;
DROP TYPE IF EXISTS ee.channel_type CASCADE;
DROP TYPE IF EXISTS ee.mcp_health_status CASCADE;
DROP TYPE IF EXISTS ee.mcp_auth_type CASCADE;
