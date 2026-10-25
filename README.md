# Inventory & Order Management System

I built this MySQL 8 database for the AmaliTech DEM03 lab. It models customers, products, orders, order lines and inventory history, then automates order placement, stock deduction, totals, discounts, customer tiers and replenishment.

I kept the project deliberately small and auditable: five core tables, two functions, three views, two triggers, two stored procedures, ten reports, sixteen data-quality checks and a transaction-safe test suite.

I wrote the full graded account in **[`docs/LAB_REPORT.md`](docs/LAB_REPORT.md)**. It covers the schema, order workflow, reporting, replenishment, performance work, testing, reflection and final verification.

## What it demonstrates

The main things I wanted the finished database to demonstrate were:

- Relational schema design with primary, unique, foreign-key and `CHECK` constraints
- `DECIMAL` money values and historical price snapshots
- Trigger-driven stock updates, inventory logging and order totals
- A JSON-based `place_order` procedure for multi-product orders
- Bulk discounts and customer tiers
- Low-stock replenishment with a locking loop
- Views, aggregate reports and window functions
- Index design and `EXPLAIN ANALYZE` benchmarking
- Transaction-safe tests and data-quality reconciliation

## Documentation map

I wrote the lab report as the graded account of the project. It follows the build order, from the schema and order workflow through reporting, replenishment, performance and testing, and ends with my reflection.

| What I want to check | Where I look |
|---|---|
| Running the project for the first time | [Quick start](#quick-start-in-mysql-workbench), then [Section 7.4: Clean-build result](docs/LAB_REPORT.md#74-clean-build-result) |
| Understanding the schema and constraints | [Section 2: Database design and schema](docs/LAB_REPORT.md#2-database-design-and-schema) |
| Tracing an order from JSON to stock | [Section 3: Order placement](docs/LAB_REPORT.md#3-order-placement-and-inventory-automation), especially [Esi's worked example](docs/LAB_REPORT.md#36-worked-example-esis-order) |
| Understanding reporting and window functions | [Section 4: Monitoring and reporting](docs/LAB_REPORT.md#4-monitoring-and-reporting) |
| Understanding indexes and the benchmark | [Section 6: Views and performance](docs/LAB_REPORT.md#6-views-and-performance) |
| Understanding locking and transaction boundaries | [Transactions and concurrency](docs/LAB_REPORT.md#39-transactions-and-concurrency) |
| Reviewing the testing and verification evidence | [Section 7: Testing and verification](docs/LAB_REPORT.md#7-testing-and-verification) |
| Reviewing the design choices and lessons | [Design decision log](docs/LAB_REPORT.md#83-design-decision-log) and [key takeaways](docs/LAB_REPORT.md#91-key-takeaways) |

I keep the companion files deliberately short. `README.md` explains how I run the project; `sql/README.md` maps the stages; `tests/README.md` explains the suite. I explain the reasoning behind them in the graded report.

## Requirements

- MySQL **8.0.16 or newer** (I used 8.0.46)
- MySQL Workbench, or the `mysql` command-line client

The local MySQL service I used during development was `MySQL80` on port `3306`.

## Quick start in MySQL Workbench

1. I open a connection to my local MySQL 8 server as a user that can create tables, indexes, views, routines and triggers. On a local lab, `root` is typical. In a shared environment, I ask for `CREATE`, `ALTER`, `DROP`, `INDEX`, `REFERENCES`, `CREATE ROUTINE`, `ALTER ROUTINE`, `EXECUTE`, `CREATE VIEW` and `TRIGGER` on the schema.
2. I open `sql/build/build.sql`.
3. I execute the whole script. It creates the `inventory_order_mgt` database, tables, indexes, functions, views, triggers, procedures and seed data.
4. I open `sql/08_reports/08_reports.sql` and execute the queries one section at a time.
5. I open `sql/09_quality/09_data_quality_checks.sql` and execute it. Every check should report `PASS`.

I rebuild from scratch by running `sql/build/build.sql` again. `sql/00_reset/00_reset.sql` drops only the lab objects in `inventory_order_mgt`; it does not drop the database.

### CLI alternative

```powershell
$env:MYSQL_PWD = "<local MySQL password>"
mysql -u root -e "source sql/build/build.sql"
mysql -u root --table -e "source sql/08_reports/08_reports.sql"
mysql -u root --table -e "source sql/09_quality/09_data_quality_checks.sql"
Remove-Item Env:MYSQL_PWD
```

I never commit the real password. `MYSQL_PWD` is inherited by child processes and is only a local convenience; on a shared machine I use `mysql -u root -p` or a login path created with `mysql_config_editor`. I keep credentials in a local `.env` or Workbench profile, never in a tracked file. A placeholder template is provided in [`.env.example`](.env.example).

## Project structure

```text
.
├── .env.example
├── README.md
├── docs/
│   └── LAB_REPORT.md          # full lab report
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

I arranged the numbered SQL stage directories as the source of truth. Each directory maps to one step in the execution order, so the folder name explains both *what* the script does and *when* it runs. I committed `sql/build/build.sql` as the assembled build of stages 00–07 so the project can be built in one step. `tests/all_tests.sql` is the assembled test suite; `tests/run_all.sql` runs the modular test files from the repository root.

## Database design

I modelled the data in five core tables:

| Table | Purpose |
|---|---|
| `customers` | Customer identity and contact details |
| `products` | Catalogue, current price, stock and reorder level |
| `orders` | Order header, customer, date and total |
| `order_items` | Products on an order, quantity, sale price, discount and line total |
| `inventory_logs` | Signed stock movements for audit and reconciliation |

These were the main design decisions I made:

- I stored `order_items.unit_price` as the price at the time of sale, not a live copy of `products.price`.
- I made `orders.total_amount` a deliberate denormalisation, maintained by a trigger.
- I used `inventory_logs` to record opening balances, sales, restocks and adjustments.
- I chose `ON DELETE RESTRICT` for foreign keys: orders and logs are audit records, so I do not allow cascading deletes.
- MySQL's default case-insensitive collation means `UNIQUE(email)` rejects case-only duplicates.
- MySQL has no partial indexes, so there is no low-stock partial index; see the performance benchmark section below for the alternative.

## Business rules

The rules I implemented are:

- Bulk discount: 5% for quantity 5–9, 10% for quantity 10 or more, applied per order line.
- Customer tiers: Bronze below 200, Silver from 200, Gold from 500.
- Low stock: `stock_quantity < reorder_level`.
- Replenishment: top each low-stock product up to twice its reorder level and log the positive change.

## Expected seed state

I load the seed orders through `place_order`, so the triggers deduct stock and write inventory logs.

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

After I call `restock_low_products()`, the mouse, monitor and laptop stand are topped up to 40, 16 and 10 respectively, and the low-stock view becomes empty.

## Transactions

I deliberately made `place_order` and `restock_low_products` leave commits to the caller. I call them inside a transaction:

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

On failure, I run `ROLLBACK`. This keeps the procedures composable and lets the tests roll back their changes.

## Tests

After a clean build, I run the assembled suite:

```powershell
$env:MYSQL_PWD = "<local MySQL password>"
mysql -u root --table -e "source tests/all_tests.sql"
Remove-Item Env:MYSQL_PWD
```

In MySQL Workbench, I open `tests/all_tests.sql` and execute the whole script.

`tests/all_tests.sql` contains the helpers and all five test files. `tests/run_all.sql` is the CLI-only alternative that uses `SOURCE`; I run it from the repository root so its `tests/sql/...` paths resolve.

Each test file wraps its changes in `START TRANSACTION` / `ROLLBACK`. A failed assertion raises `SQLSTATE 45000` and stops the script.

My run on MySQL 8.0.46 produced:

```text
01_constraints_test passed
02_functions_test passed
03_order_tests passed
04_inventory_tests passed
05_views_test passed
```

I wrote the suite to cover constraint violations, tier and discount boundaries, multi-product orders, caller-price rejection, historical price snapshots, oversell rejection, JSON validation, restock idempotence and the reporting views. I ran both the assembled suite and the modular CLI runner, and both completed with all five suites passing.

I explain the assertion design, the issues I found and the coverage gaps in [Section 7: Testing and verification](docs/LAB_REPORT.md#7-testing-and-verification) of the report.

## Data-quality checks

I wrote `sql/09_quality/09_data_quality_checks.sql` to run 16 read-only integrity checks:

```powershell
mysql -u root --table -e "source sql/09_quality/09_data_quality_checks.sql"
```

In my run, every row reported `PASS`, including stock-to-log reconciliation, order-total reconciliation, sale-log matching, discount rules, tier rules and low-stock view consistency. I explain what each check proves and where the gaps are in [Section 4.5: Data-quality checks](docs/LAB_REPORT.md#45-data-quality-checks).

## Performance benchmark

I wrote `sql/10_benchmark/10_performance_benchmark.sql` to create a 200,000-row temporary table and compare the customer-order query before and after adding `(customer_id, order_date)`.

```powershell
mysql -u root --table -e "source sql/10_benchmark/10_performance_benchmark.sql"
```

My measurements on MySQL 8.0.46 were:

| Plan | Access | Rows examined | Time |
|---|---|---|---:|
| Before index | full table scan + sort | 200,000 | 31.4 ms (31–42 ms observed) |
| After index | covering index lookup, reverse order | 40 | 0.065 ms (0.065–0.077 ms observed) |

The exact numbers depend on the machine and buffer state; the plan shape is the important result. The script runs `EXPLAIN ANALYZE` before and after the index and prints both plans, so I compare the access type and rows examined rather than trusting a single millisecond figure. I explain how to read the plans in [Section 6.5: What the benchmark shows and does not show](docs/LAB_REPORT.md#65-what-the-benchmark-shows-and-does-not-show).

## Verification snapshot

I recorded these results after the final clean run:

- **MySQL:** 8.0.46, local `MySQL80`, port 3306.
- **Clean build:** I ran `sql/build/build.sql` through seed data.
- **Tests:** I ran all five files through both runners and they passed.
- **Data quality:** all 16 checks returned `PASS`.
- **Benchmark:** my full-scan run took 31.4 ms (31–42 ms observed); the covering-index run took 0.065 ms (0.065–0.077 ms observed).
- **Seed state:** five orders totalling 1030.99; stock 105 / 12 / 39 / 2 / 0; three low-stock products.
- **Last verified:** 25 October 2026, after I reorganised the SQL stages and tests.

## Troubleshooting

These are the problems I ran into or deliberately checked while getting the build to run:

- **`CHECK` constraints seem ignored:** I confirm `SELECT VERSION();` is 8.0.16 or newer.
- **`Error 1418` when creating a function:** I declare it `DETERMINISTIC`, `NO SQL` or `READS SQL DATA`, or enable `log_bin_trust_function_creators`.
- **`Error 1419` when creating functions/triggers:** the account lacks `SET_USER_ID` (or the deprecated `SUPER`) while binary logging is enabled. I use a privileged local user, or ask an administrator to enable `log_bin_trust_function_creators`.
- **`DELIMITER` errors in Workbench:** I run the whole `sql/build/build.sql` script rather than individual statements inside a routine.
- **`Can't connect`:** I confirm the MySQL80 service is running and Workbench is using port 3306.
- **`Access denied for user`:** I set `MYSQL_PWD` in the same shell session as the command, or use `mysql -u root -p`; I confirm the user and host match the account.
- **Reset a failed run:** I run `sql/00_reset/00_reset.sql`, then `sql/build/build.sql`.
