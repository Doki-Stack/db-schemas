#!/bin/bash
set -euo pipefail

ADMIN_URL="${DATABASE_URL}"
SERVICE_URL=$(echo "$DATABASE_URL" | sed 's/app_admin:test_password/app_service:service_password/')

ORG_A="a0000000-0000-0000-0000-000000000001"
ORG_B="b0000000-0000-0000-0000-000000000002"

echo "=== RLS Validation ==="

echo "Step 1: Creating test data as admin..."
psql "$ADMIN_URL" <<SQL
  INSERT INTO orgs (id, name, slug) VALUES
    ('${ORG_A}'::uuid, 'Test Org A', 'test-org-a'),
    ('${ORG_B}'::uuid, 'Test Org B', 'test-org-b')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO users (id, org_id, auth0_sub, email, display_name, role) VALUES
    ('11111111-1111-1111-1111-111111111111'::uuid, '${ORG_A}'::uuid,
     'auth0|test-a', 'a@test.com', 'User A', 'operator'),
    ('22222222-2222-2222-2222-222222222222'::uuid, '${ORG_B}'::uuid,
     'auth0|test-b', 'b@test.com', 'User B', 'operator')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO tasks (id, org_id, user_id, title, status) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '${ORG_A}'::uuid,
     '11111111-1111-1111-1111-111111111111'::uuid, 'Org A Task', 'pending'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, '${ORG_B}'::uuid,
     '22222222-2222-2222-2222-222222222222'::uuid, 'Org B Task', 'pending')
  ON CONFLICT (id) DO NOTHING;

  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_service;
  GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_service;
SQL

echo "Test data created."

echo "Step 2: Verifying Org A isolation..."
RESULT=$(psql "$SERVICE_URL" -t -c "
  SET app.current_org_id = '${ORG_A}';
  SELECT count(*) FROM tasks;
")
RESULT=$(echo "$RESULT" | tr -d ' ')
if [ "$RESULT" != "1" ]; then
  echo "FAIL: Org A should see exactly 1 task, got $RESULT"
  exit 1
fi
echo "  PASS: Org A sees only its own tasks"

echo "Step 3: Verifying cross-tenant isolation..."
RESULT=$(psql "$SERVICE_URL" -t -c "
  SET app.current_org_id = '${ORG_A}';
  SELECT count(*) FROM tasks WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid;
")
RESULT=$(echo "$RESULT" | tr -d ' ')
if [ "$RESULT" != "0" ]; then
  echo "FAIL: Org A should NOT see Org B tasks"
  exit 1
fi
echo "  PASS: Org A cannot see Org B tasks"

echo "Step 4: Verifying INSERT protection..."
INSERT_RESULT=$(psql "$SERVICE_URL" -c "
  SET app.current_org_id = '${ORG_A}';
  INSERT INTO tasks (id, org_id, user_id, title, status)
  VALUES (gen_random_uuid(), '${ORG_B}'::uuid,
          '11111111-1111-1111-1111-111111111111'::uuid, 'Sneaky Task', 'pending');
" 2>&1 || true)
if echo "$INSERT_RESULT" | grep -q "ERROR\|violates"; then
  echo "  PASS: Cannot insert with wrong org_id"
else
  echo "FAIL: Should not be able to insert with wrong org_id"
  exit 1
fi

echo "Step 5: Verifying missing org_id behavior..."
RESULT=$(psql "$SERVICE_URL" -t -c "
  RESET app.current_org_id;
  SELECT count(*) FROM tasks;
")
RESULT=$(echo "$RESULT" | tr -d ' ')
if [ "$RESULT" != "0" ]; then
  echo "FAIL: Missing org_id should return 0 rows, got $RESULT"
  exit 1
fi
echo "  PASS: Missing org_id returns 0 rows"

echo "Step 6: Verifying audit_logs immutability..."
psql "$SERVICE_URL" -c "
  SET app.current_org_id = '${ORG_A}';
  INSERT INTO audit_logs (org_id, actor_type, action, resource_type, details)
  VALUES ('${ORG_A}'::uuid, 'system', 'test.rls_validation', 'test', '{}'::jsonb);
" || { echo "FAIL: Should be able to INSERT audit logs"; exit 1; }
echo "  PASS: Can INSERT audit logs"

UPDATE_RESULT=$(psql "$SERVICE_URL" -c "
  SET app.current_org_id = '${ORG_A}';
  UPDATE audit_logs SET action = 'tampered' WHERE action = 'test.rls_validation';
" 2>&1 || true)
if echo "$UPDATE_RESULT" | grep -q "UPDATE 0\|ERROR"; then
  echo "  PASS: Cannot UPDATE audit logs"
else
  echo "FAIL: Should not be able to UPDATE audit logs"
  exit 1
fi

echo "Step 7: Verifying all tenant-scoped tables..."
TABLES="users tasks plans approvals scanner_contexts policy_rules cost_limits"
for table in $TABLES; do
  RESULT=$(psql "$SERVICE_URL" -t -c "
    SET app.current_org_id = '${ORG_A}';
    SELECT count(*) FROM $table WHERE org_id = '${ORG_B}'::uuid;
  ")
  RESULT=$(echo "$RESULT" | tr -d ' ')
  if [ "$RESULT" != "0" ]; then
    echo "FAIL: Table $table leaking cross-tenant data"
    exit 1
  fi
  echo "  PASS: $table - no cross-tenant data visible"
done

echo "Step 8: Verifying orgs table accessibility..."
RESULT=$(psql "$SERVICE_URL" -t -c "SELECT count(*) FROM orgs;")
RESULT=$(echo "$RESULT" | tr -d ' ')
if [ "$RESULT" -lt "2" ]; then
  echo "FAIL: orgs table should be accessible without org_id filter"
  exit 1
fi
echo "  PASS: orgs table accessible without RLS"

echo "Cleaning up test data..."
psql "$ADMIN_URL" -c "
  DELETE FROM audit_logs WHERE action = 'test.rls_validation';
  DELETE FROM tasks WHERE id IN (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid
  );
  DELETE FROM users WHERE id IN (
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid
  );
  DELETE FROM orgs WHERE id IN ('${ORG_A}'::uuid, '${ORG_B}'::uuid);
"

echo ""
echo "=== RLS Validation Complete: ALL TESTS PASSED ==="
