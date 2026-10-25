# Tests

The modular test sources live in `tests/sql/` and run in numeric order. `tests/all_tests.sql` is the assembled MySQL Workbench-friendly suite; `tests/run_all.sql` is the CLI runner for the modular files.

| File | Focus |
|---|---|
| `tests/sql/00_test_helpers.sql` | `assert_true` and `assert_raises` helpers |
| `tests/sql/01_constraints_test.sql` | Constraint and trigger rejection paths |
| `tests/sql/02_functions_test.sql` | Tier and discount boundary values |
| `tests/sql/03_order_tests.sql` | Order placement, pricing, stock and rollback |
| `tests/sql/04_inventory_tests.sql` | Restock idempotence and ledger reconciliation |
| `tests/sql/05_views_test.sql` | Reporting-view row counts and values |

## Run the assembled suite

```powershell
mysql -u root --table -e "source tests/all_tests.sql"
```

In MySQL Workbench, open `tests/all_tests.sql` and execute the whole script.

## Run the modular suite

Run from the repository root so the `SOURCE tests/sql/...` paths resolve:

```powershell
mysql -u root --table -e "source tests/run_all.sql"
```

Every test wraps its DML in `START TRANSACTION` / `ROLLBACK`, so a successful run leaves the seed state unchanged. A failed assertion raises `SQLSTATE 45000` and stops the script.

The `.sql` files in `tests/sql/` are the source of truth. If you change one, update `tests/all_tests.sql` so the assembled suite stays in sync, or use `tests/run_all.sql` to run the modular files directly.
