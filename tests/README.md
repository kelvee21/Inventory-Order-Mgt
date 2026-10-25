# Tests

I wrote five transaction-wrapped test files and two assertion helpers. `tests/all_tests.sql` is the assembled MySQL Workbench-friendly suite; `tests/run_all.sql` is the CLI runner for the modular files in `tests/sql/`.

There are **72 assertions**. A successful run leaves the seed state unchanged because every file ends with `ROLLBACK`. A failed assertion raises `SQLSTATE 45000` and stops the script.

## What I cover

| File | Assertions | Focus | Where I explain it |
|---|---:|---|---|
| `tests/sql/00_test_helpers.sql` | 0 | `assert_true` and `assert_raises` | [7.2 Assertion helpers](../docs/LAB_REPORT.md#72-assertion-helpers) |
| `tests/sql/01_constraints_test.sql` | 17 | Duplicate and case-only duplicate email, invalid email, blank name, negative price/stock/reorder, duplicate product name, unknown customer/order/product, duplicate line, zero quantity, invalid discount, negative stock update, zero inventory change, invalid reason | [7.3 Test files](../docs/LAB_REPORT.md#73-test-files) |
| `tests/sql/02_functions_test.sql` | 12 | Tier boundaries at 0, 199.99, 200, 499.99, 500 and 1000; discount boundaries at 0, 4, 5, 9, 10 and 100 | [7.3](../docs/LAB_REPORT.md#73-test-files) |
| `tests/sql/03_order_tests.sql` | 21 | Multi-product pricing, 5% and 10% discounts, stock deduction, one sale log per line, historical price snapshot, caller price ignored, order-total recalculation, oversell rollback, unknown customer/product, empty/non-array/duplicate/zero JSON, null date default | [7.3](../docs/LAB_REPORT.md#73-test-files) |
| `tests/sql/04_inventory_tests.sql` | 12 | Seed low-stock count, top-up to twice reorder level, non-low product unchanged, positive restock log, idempotent second call, ledger reconciliation | [7.3](../docs/LAB_REPORT.md#73-test-files) |
| `tests/sql/05_views_test.sql` | 10 | Order-summary row count and values, low-stock membership, customer spend and tiers, total spend | [7.3](../docs/LAB_REPORT.md#73-test-files) |

The test files, assertion helpers and coverage gaps are summarised in [Section 7](../docs/LAB_REPORT.md#7-testing-and-verification).

## How my harness works

`assert_true(condition, label)` raises `SQLSTATE 45000` with the label when the condition is `NULL` or false. Treating `NULL` as failure matters: a subquery that returns no row makes a comparison `NULL`, and a naive `IF NOT condition` would also treat that as false, but the explicit check documents the intent.

`assert_raises(sql_text, expected_state, label)` prepares and executes a statement, catches `SQLEXCEPTION` in a nested block, records the SQLSTATE, and fails if the statement succeeded or raised a different state. It uses dynamic SQL because its job is to execute a statement supplied as a string; it must never be exposed to untrusted callers.

I chose the transaction pattern deliberately:

- The helpers are created **before** any transaction, because DDL causes an implicit commit.
- Each test file starts with `START TRANSACTION` and ends with `ROLLBACK`.
- The files use only `INSERT`, `UPDATE`, `CALL` and `SELECT` inside the transaction.
- New rows use explicit ids (100 and above) so they cannot collide with seed rows.
- A failure stops the script; the open transaction is rolled back when the session ends.

I explain handler scope, the prepared-statement cleanup path and the auto-increment gap left by rolled-back inserts in [Section 7.2: Assertion helpers](../docs/LAB_REPORT.md#72-assertion-helpers).

## How I run the assembled suite

From the repository root:

```powershell
$env:MYSQL_PWD = "<local MySQL password>"
mysql -u root --table -e "source tests/all_tests.sql"
Remove-Item Env:MYSQL_PWD
```

In MySQL Workbench, I open `tests/all_tests.sql` and execute the whole script. I do not execute the statements one at a time; the `DELIMITER` blocks and the transaction boundary assume a single run.

## How I run the modular suite

I run this from the repository root so the `SOURCE tests/sql/...` paths resolve:

```powershell
$env:MYSQL_PWD = "<local MySQL password>"
mysql -u root --table -e "source tests/run_all.sql"
Remove-Item Env:MYSQL_PWD
```

Both runners should agree. If one passes and the other fails, the assembled file is stale or a path is wrong.

`MYSQL_PWD` is inherited by every `mysql` process in the same shell. If I open a new terminal, I set it again, or omit it and add `-p` so the client prompts. I never commit a real password.

## Expected output

My clean run prints:

```text
01_constraints_test passed
02_functions_test passed
03_order_tests passed
04_inventory_tests passed
05_views_test passed
```

The helper script also prints `Test helpers created.` before the five suites.

## How I add a test

When I add a test, I follow these steps:

1. **I state the behaviour in one sentence.** For example: “A price change after a sale does not change the historical line price.”
2. **I choose the smallest level.** A function boundary belongs in `02_functions_test.sql`; a procedure/trigger interaction belongs in `03_order_tests.sql`; a view value belongs in `05_views_test.sql`.
3. **I arrange deterministic data.** I use explicit ids or the seed, and I avoid relying on auto-increment values.
4. **I act once.** I call the procedure or run the statement.
5. **I assert the state, not the implementation.** I check the row values and counts a user would care about.
6. **I clean up.** I rely on the file's `ROLLBACK`, and I do not add DDL inside the transaction.
7. **I update both runners.** I add the test to the modular file, then regenerate or manually update `tests/all_tests.sql`. I also run `tests/run_all.sql`.

A positive assertion:

```sql
CALL assert_true(
  (SELECT stock_quantity FROM products WHERE product_id = 100) = 95,
  'cable stock is deducted'
);
```

A negative assertion:

```sql
CALL assert_raises(
  'INSERT INTO customers (full_name, email)
   VALUES (''Duplicate'', ''ama@example.com'')',
  '23000',
  'duplicate email is rejected'
);
```

Inside the SQL string, I double the single quotes. The expected state is the five-character SQLSTATE, not the MySQL error number: `23000` for integrity violations, `HY000` for many `CHECK` failures, and `45000` for the project's own `SIGNAL`s.

I list the cases I did not test, including the concurrency test I would add next, in [Section 7.7: Coverage gaps](../docs/LAB_REPORT.md#77-coverage-gaps).

## How I diagnose a failure

| Symptom | Likely cause | What I do |
|---|---|---|
| `Expected an error but the statement succeeded` | Constraint missing, wrong data, or test using the wrong key | I inspect the constraint and the row, then run the statement manually |
| `Statement failed with an unexpected SQLSTATE` | Wrong expected class, or a different layer rejected it | I check whether it is `23000`, `HY000` or `45000`, then adjust the test or the code |
| `Unknown column` / `Unknown table` | Build not run, wrong database, or stale assembled file | I run `USE inventory_order_mgt;` and rerun the build |
| `Duplicate entry` in setup | A previous test did not roll back, or an explicit id already exists | I rebuild and ensure every file ends with `ROLLBACK` |
| `Check constraint is violated` | Test value outside the allowed range | I fix the test data or the constraint |
| `Deadlock` / lock wait | A concurrent session holds a lock | I roll back and inspect `SHOW ENGINE INNODB STATUS` |
| `DELIMITER` syntax error | Ran a routine body as separate statements | I run the whole script |
| `SOURCE` file not found | Wrong working directory | I run from the repository root |
| Test passes alone but fails in the suite | Earlier file left state behind, or the assembly is stale | I run the suite in order, check each `ROLLBACK`, and rebuild |
| Quality check fails after tests | A test did not roll back, or a manual edit changed data | I rebuild and investigate rather than deleting rows |

I explain the failures that shaped the harness in [Section 7.6: Issues I found and fixed](../docs/LAB_REPORT.md#76-issues-i-found-and-fixed).

## What I do not cover

I deliberately kept the suite focused. It does **not** cover:

- Two-session concurrency: simultaneous orders for the same product, the oversell race, gap locks or deadlocks.
- Large datasets, query plans or benchmark thresholds.
- Malformed JSON types beyond the documented shape, such as a string quantity.
- Duplicate sale logs; the quality check has the gap described in Section 4.5.
- Time-zone behaviour, backup/restore, replication or privilege tests.
- DDL changes and migration rollback.

The most valuable next test I would add is a concurrency test, because the locking design is the most subtle part of the project. I discuss the rest in [Section 7.7: Coverage gaps](../docs/LAB_REPORT.md#77-coverage-gaps).

## Keeping the suite in sync

The `.sql` files in `tests/sql/` are the source of truth. If I change one, I update `tests/all_tests.sql` so the assembled suite stays in sync, or I use `tests/run_all.sql` to run the modular files directly.

The tests assume a clean build with the seed data. If I have run the reports, the benchmark or an experiment that changed data, I rerun `sql/build/build.sql` before investigating a test failure.

The test runner account needs `EXECUTE` on the helper procedures and the project procedures, plus `SELECT`, `INSERT` and `UPDATE` on the tables. Creating the helpers at runtime also needs `CREATE ROUTINE`; in a shared environment, an administrator can create the helpers once and grant `EXECUTE`.
