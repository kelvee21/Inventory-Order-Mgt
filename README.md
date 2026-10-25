# Inventory & Order Management System

A MySQL 8 project for the AmaliTech DEM03 lab. It models customers, products, orders, order lines and inventory history, then automates order placement, stock deduction, totals, discounts, customer tiers and replenishment.

The project is deliberately small and auditable: five core tables, two functions, three views, two triggers, two stored procedures, ten reports, sixteen data-quality checks and a transaction-safe test suite.

## What it demonstrates

- Relational schema design with primary, unique, foreign-key and `CHECK` constraints
- `DECIMAL` money values and historical price snapshots
- Trigger-driven stock updates, inventory logging and order totals
- A JSON-based `place_order` procedure for multi-product orders
- Bulk discounts and customer tiers
- Low-stock replenishment with a locking loop
- Views, aggregate reports and window functions
- Index design and `EXPLAIN ANALYZE` benchmarking
- Transaction-safe tests and data-quality reconciliation

## Requirements

- MySQL **8.0.16 or newer** (8.0.46 is used here)
- MySQL Workbench, or the `mysql` command-line client

The local MySQL service used during development was `MySQL80` on port `3306`.

## Quick start in MySQL Workbench

1. Open a connection to your local MySQL 8 server as a user with `CREATE` and `CREATE ROUTINE` privileges.
2. Open `sql/build/build.sql`.
3. Execute the whole script. It creates the `inventory_order_mgt` database, tables, indexes, functions, views, triggers, procedures and seed data.
4. Open `sql/08_reports/08_reports.sql` and execute the queries one section at a time.
5. Open `sql/09_quality/09_data_quality_checks.sql` and execute it. Every check should report `PASS`.

To rebuild from scratch, run `sql/build/build.sql` again. `sql/00_reset/00_reset.sql` drops only the lab objects in `inventory_order_mgt`; it does not drop the database.

### CLI alternative

```powershell
$env:MYSQL_PWD = "<your local MySQL password>"
mysql -u root -e "source sql/build/build.sql"
mysql -u root --table -e "source sql/08_reports/08_reports.sql"
mysql -u root --table -e "source sql/09_quality/09_data_quality_checks.sql"
Remove-Item Env:MYSQL_PWD
```

Do not commit the real password. Keep it in your Workbench profile, a local `.env`, or a shell environment variable. A placeholder template is provided in [`.env.example`](.env.example).

## Project structure

```text
.
├── .env.example
├── README.md
├── sql/
│   ├── 00_reset/00_reset.sql
│   ├── 01_schema/01_schema.sql
│   ├── 02_indexes/02_indexes.sql
│   ├── 03_functions/03_functions.sql
│   ├── 04_views/04_views.sql
│   ├── 05_triggers/05_triggers.sql
│   ├── 06_procedures/06_procedures.sql
│   ├── 07_seed/07_seed_data.sql
│   ├── 08_reports/08_reports.sql
│   ├── 09_quality/09_data_quality_checks.sql
│   ├── 10_benchmark/10_performance_benchmark.sql
│   ├── build/build.sql        # assembled from stages 00-07
│   └── README.md              # stage map and run order
└── tests/
    ├── sql/                   # test sources, run in numeric order
    │   ├── 00_test_helpers.sql
    │   ├── 01_constraints_test.sql
    │   ├── 02_functions_test.sql
    │   ├── 03_order_tests.sql
    │   ├── 04_inventory_tests.sql
    │   └── 05_views_test.sql
    ├── all_tests.sql          # assembled, Workbench-friendly
    ├── run_all.sql            # CLI SOURCE runner
    └── README.md
```

The numbered SQL stage directories are the source of truth. Each directory maps to one step in the execution order, so the folder name explains both *what* the script does and *when* it runs. `sql/build/build.sql` is the assembled build of stages 00–07 and is committed so the project can be built in one step. `tests/all_tests.sql` is the assembled test suite; `tests/run_all.sql` runs the modular test files from the repository root.

## Database design

| Table | Purpose |
|---|---|
| `customers` | Customer identity and contact details |
| `products` | Catalogue, current price, stock and reorder level |
| `orders` | Order header, customer, date and total |
| `order_items` | Products on an order, quantity, sale price, discount and line total |
| `inventory_logs` | Signed stock movements for audit and reconciliation |

Key decisions:

- `order_items.unit_price` is the price at the time of sale, not a live copy of `products.price`.
- `orders.total_amount` is a deliberate denormalisation, maintained by a trigger.
- `inventory_logs` records opening balances, sales, restocks and adjustments.
- Foreign keys use `ON DELETE RESTRICT`: orders and logs are audit records, so cascading deletes are not allowed.
- MySQL's default case-insensitive collation means `UNIQUE(email)` rejects case-only duplicates.
- MySQL has no partial indexes, so there is no low-stock partial index; see the performance benchmark section below for the alternative.

## Business rules

- Bulk discount: 5% for quantity 5–9, 10% for quantity 10 or more, applied per order line.
- Customer tiers: Bronze below 200, Silver from 200, Gold from 500.
- Low stock: `stock_quantity < reorder_level`.
- Replenishment: top each low-stock product up to twice its reorder level and log the positive change.

## Expected seed state

The seed loads orders through `place_order`, so the triggers deduct stock and write inventory logs.

| Product | Opening stock | Stock after seed | Reorder |
|---|---:|---:|---:|
| USB-C Cable | 120 | 105 | 30 |
| Wireless Mouse | 15 | 12 | 20 |
| Mechanical Keyboard | 40 | 39 | 10 |
| 27in Monitor | 5 | 2 | 8 |
| Laptop Stand | 0 | 0 | 5 |

Order totals: **50.50, 338.99, 498.00, 126.50, 17.00**. The fourth total is 126.50 rather than the lesson's 135.00 because the 10% bulk discount is applied to ten cables.

Customer spend and tiers:

| Customer | Spend | Tier |
|---|---:|---|
| Ama Mensah | 548.50 | Gold |
| Kofi Boateng | 355.99 | Silver |
| Esi Owusu | 126.50 | Bronze |
| Yaw Darko | 0.00 | Bronze |

After `restock_low_products()`, the mouse, monitor and laptop stand are topped up to 40, 16 and 10 respectively, and the low-stock view becomes empty.

## Transactions

`place_order` and `restock_low_products` do **not** commit internally. Call them inside a transaction:

```sql
START TRANSACTION;
CALL place_order(
  3,
  JSON_ARRAY(
    JSON_OBJECT('product_id', 1, 'quantity', 5),
    JSON_OBJECT('product_id', 4, 'quantity', 1)
  ),
  CURRENT_DATE,
  @order_id
);
COMMIT;
```

On failure, run `ROLLBACK`. This keeps the procedures composable and lets the tests roll back their changes.

## Tests

After a clean build, run the assembled suite:

```powershell
$env:MYSQL_PWD = "<your local MySQL password>"
mysql -u root --table -e "source tests/all_tests.sql"
Remove-Item Env:MYSQL_PWD
```

In MySQL Workbench, open `tests/all_tests.sql` and execute the whole script.

`tests/all_tests.sql` contains the helpers and all five test files. `tests/run_all.sql` is the CLI-only alternative that uses `SOURCE`; run it from the repository root so its `tests/sql/...` paths resolve.

Each test file wraps its changes in `START TRANSACTION` / `ROLLBACK`. A failed assertion raises `SQLSTATE 45000` and stops the script.

Measured result on MySQL 8.0.46:

```text
01_constraints_test passed
02_functions_test passed
03_order_tests passed
04_inventory_tests passed
05_views_test passed
```

The suite covers constraint violations, tier and discount boundaries, multi-product orders, caller-price rejection, historical price snapshots, oversell rejection, JSON validation, restock idempotence and the reporting views. Both the assembled suite and the modular CLI runner completed with all five suites passing.

## Data-quality checks

`sql/09_quality/09_data_quality_checks.sql` runs 16 read-only integrity checks:

```powershell
mysql -u root --table -e "source sql/09_quality/09_data_quality_checks.sql"
```

Expected result: every row reports `PASS`, including stock-to-log reconciliation, order-total reconciliation, sale-log matching, discount rules, tier rules and low-stock view consistency.

## Performance benchmark

`sql/10_benchmark/10_performance_benchmark.sql` creates a 200,000-row temporary table and compares the customer-order query before and after adding `(customer_id, order_date)`.

```powershell
mysql -u root --table -e "source sql/10_benchmark/10_performance_benchmark.sql"
```

Measured on MySQL 8.0.46:

| Plan | Access | Rows examined | Time |
|---|---|---|---:|
| Before index | full table scan + sort | 200,000 | 31.4 ms (31–42 ms observed) |
| After index | covering index lookup, reverse order | 40 | 0.065 ms (0.065–0.077 ms observed) |

The exact numbers depend on the machine and buffer state; the plan shape is the important result. The benchmark script contains the full `EXPLAIN ANALYZE` output.

## Verification snapshot

- **MySQL:** 8.0.46, local `MySQL80`, port 3306.
- **Clean build:** `sql/build/build.sql` completed through seed data.
- **Tests:** all five files passed through both runners.
- **Data quality:** all 16 checks returned `PASS`.
- **Benchmark:** full scan 31.4 ms (31–42 ms observed); covering index 0.065 ms (0.065–0.077 ms observed).
- **Seed state:** five orders totalling 1030.99; stock 105 / 12 / 39 / 2 / 0; three low-stock products.
- **Last verified:** 25 October 2026, after the SQL stage and test reorganisation.

## Troubleshooting

- **`CHECK` constraints seem ignored:** confirm `SELECT VERSION();` is 8.0.16 or newer.
- **Error 1418 when creating functions/triggers:** run as a privileged local user, or ask an administrator to enable `log_bin_trust_function_creators`.
- **`DELIMITER` errors in Workbench:** run the whole `sql/build/build.sql` script rather than individual statements inside a routine.
- **`Can't connect`:** confirm the MySQL80 service is running and Workbench is using port 3306.
- **Reset a failed run:** run `sql/00_reset/00_reset.sql`, then `sql/build/build.sql`.
