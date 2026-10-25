# SQL pipeline

I arranged each numbered directory as one stage of the pipeline. Directory order is execution order. The stage files are the executable source of truth; `build/build.sql` is the assembled build of stages 00–07 that I use for a one-step run.

```text
00_reset -> 01_schema -> 02_indexes -> 03_functions -> 04_views
        -> 05_triggers -> 06_procedures -> 07_seed
        -> 08_reports -> 09_quality -> 10_benchmark
```

## Stage map

| Stage | File | Depends on | What I built | Where I explain it |
|---:|---|---|---|---|
| 0 | `00_reset/00_reset.sql` | Nothing | Reset the lab objects inside `inventory_order_mgt` without dropping the database | [Design goal](../docs/LAB_REPORT.md#21-goal) |
| 1 | `01_schema/01_schema.sql` | 0 | Created the five tables, keys, `CHECK` constraints and FK-supporting indexes | [Schema design](../docs/LAB_REPORT.md#2-database-design-and-schema) |
| 2 | `02_indexes/02_indexes.sql` | 1 | Added `idx_orders_order_date` for date-range reports | [Index inventory](../docs/LAB_REPORT.md#62-index-inventory) |
| 3 | `03_functions/03_functions.sql` | 1 | Created `customer_tier` and `bulk_discount_rate` | [Schema and rules](../docs/LAB_REPORT.md#2-database-design-and-schema) |
| 4 | `04_views/04_views.sql` | 1, 3 | Created `v_order_summary`, `v_low_stock` and `v_customer_spend` | [Views](../docs/LAB_REPORT.md#42-views) |
| 5 | `05_triggers/05_triggers.sql` | 1, 3 | Priced each line, deducted stock, wrote the ledger and updated the order total | [Triggers](../docs/LAB_REPORT.md#35-triggers) |
| 6 | `06_procedures/06_procedures.sql` | 1, 3, 5 | Created `place_order` and `restock_low_products` | [Order validation](../docs/LAB_REPORT.md#34-validation-in-place_order) and [restock loop](../docs/LAB_REPORT.md#53-why-a-while-loop) |
| 7 | `07_seed/07_seed_data.sql` | 1, 3, 5, 6 | Loaded deterministic customers and products, then created five orders through `place_order` | [Seed data](../docs/LAB_REPORT.md#26-seed-data) |
| 8 | `08_reports/08_reports.sql` | 0–7 | Ran ten analytical reports | [Reports](../docs/LAB_REPORT.md#43-reports) |
| 9 | `09_quality/09_data_quality_checks.sql` | 0–7 | Ran sixteen read-only PASS/FAIL integrity checks | [Data-quality checks](../docs/LAB_REPORT.md#45-data-quality-checks) |
| 10 | `10_benchmark/10_performance_benchmark.sql` | 0 | Built a 200,000-row temporary table and compared a scan with a covering index | [Benchmark](../docs/LAB_REPORT.md#64-benchmark) and [interpretation](../docs/LAB_REPORT.md#65-what-the-benchmark-shows-and-does-not-show) |

Stage 0 does not drop the database itself. It drops the lab objects inside `inventory_order_mgt`, so it is safe to rerun on a local lab database but not safe as a production reset.

## How I run the pipeline

From the repository root, in one shell:

```powershell
$env:MYSQL_PWD = "<local MySQL password>"
mysql -u root -e "source sql/build/build.sql"
mysql -u root --table -e "source sql/08_reports/08_reports.sql"
mysql -u root --table -e "source sql/09_quality/09_data_quality_checks.sql"
mysql -u root --table -e "source sql/10_benchmark/10_performance_benchmark.sql"
Remove-Item Env:MYSQL_PWD
```

`MYSQL_PWD` is read by every `mysql` process in the same session. If I open a new terminal, I set it again, or omit it and add `-p` to each command so the client prompts. I never commit a real password.

The build prints one confirmation per stage:

```text
Database reset complete.
Schema created.
Additional indexes created.
Functions created.
Views created.
Triggers created.
Procedures created.
Seed data loaded.
```

The reports return ten result sets. The quality script returns sixteen rows whose `status` column is `PASS`. The benchmark returns a phase label and an `EXPLAIN ANALYZE` plan for each side of the index comparison.

## What I built at each stage

### 0. Reset

I drop views first, then tables, then procedures and functions. Views depend on tables and functions; triggers disappear with their table. I set `FOREIGN_KEY_CHECKS = 0` so the tables can be dropped in any order without FK errors, then reset it to `1` immediately afterwards.

This is a **rebuild**, not a migration. It is appropriate for coursework and reproducible demos. It would destroy production data.

### 1. Schema

I start with the schema because every later stage assumes its names and rules. I declared the FK-supporting indexes inline rather than leaving them to InnoDB's automatic index creation. That kept the index names predictable and avoided a redundant single-column index. I explain the schema and its constraints in Section 2 of the report.

### 2. Indexes

I added only one index here: `idx_orders_order_date`. All other access paths are either the primary key, a unique key, or a composite index declared in the schema to support a foreign key. I kept this stage deliberately small; it separates “indexes required by the model” from “indexes added for a known query”.

I test index changes on a scratch copy rather than editing the committed stage for an experiment.

### 3. Functions

I wrote both functions as deterministic and `NO SQL`:

- `customer_tier(spend)` maps spend to Bronze, Silver or Gold.
- `bulk_discount_rate(quantity)` maps quantity to 0%, 5% or 10%.

They are called by the line trigger and by the customer-spend view. Because they are deterministic, MySQL can evaluate them consistently and the binary log accepts them without the declaration error. They still need the usual routine privileges.

### 4. Views

I created three views to give readers stable names:

- `v_order_summary`: one row per order, with customer name and total units.
- `v_low_stock`: products where `stock_quantity < reorder_level`.
- `v_customer_spend`: lifetime spend per customer, with a tier.

`v_order_summary` and `v_customer_spend` contain aggregation, so MySQL is likely to materialise them into an internal temporary table for the query. `v_low_stock` is simple enough to merge. Neither is a persistent materialised view. I explain the views in Section 4.2 and the reporting limitations in Section 4.7.

### 5. Triggers

I wrote two row-level triggers on `order_items`:

- `BEFORE INSERT` validates quantity, locks the product row, snapshots the catalogue price, applies the bulk discount and calculates the line total.
- `AFTER INSERT` locks the product row again, checks stock, deducts it, writes an `inventory_logs` row and adds the line total to `orders.total_amount`.

The `FOR UPDATE` reads are the concurrency control. They serialise two orders that touch the same product, so the stock check cannot pass twice. I cover transaction boundaries, row locking and the oversell race in Section 3.9.

### 6. Procedures

My `place_order` procedure accepts a JSON array, validates every item, rejects duplicate products, checks the customer, inserts the header, inserts the lines through `INSERT ... SELECT`, and returns the new order id. It does not commit.

My `restock_low_products` procedure loops over low-stock products, locks one at a time, tops it up to twice its reorder level and writes a positive ledger row. It also leaves transaction control to the caller.

I explain the order contract and validation in Sections 3.3 and 3.4, and the restock loop in Section 5.3.

### 7. Seed

The seed I wrote inserts four customers and five products, then creates five orders through `place_order`. It does not insert order lines directly, so the triggers deduct stock, apply discounts, write logs and update totals exactly as they would for a real caller.

The expected seed state is five orders totalling `1030.99`, stock `105 / 12 / 39 / 2 / 0`, and three low-stock products. I explain every number in Section 2.6.

### 8. Reports

I wrote ten read-only reports that can be rerun. They cover customer summaries, order detail, low stock, product sales, inventory reconciliation, daily and monthly sales, ranking and customer share.

I run them one at a time in Workbench and compare each result with Section 4.3. If the data grew by a factor of a thousand, the reporting limitations in Section 4.7 would matter.

### 9. Quality checks

I wrote sixteen set-based, read-only checks. They prove invariants such as:

- stock equals the sum of its ledger rows;
- each order total equals the sum of its line totals;
- every sale line has one matching sale log;
- discounts and tiers follow the function rules;
- the low-stock view agrees with the base table.

A `PASS` means “no violating rows”, not “the data is perfect”. I list the gaps in Section 4.5, including duplicate sale logs and the absence of a check for negative stock history.

### 10. Benchmark

I wrote the benchmark to create a temporary `big_orders` table with 200,000 rows, run the customer-order query with `EXPLAIN ANALYZE`, add `(customer_id, order_date)`, and run the same query again. The temporary table is dropped at the end, so the lab data is untouched.

The expected change is from a full scan plus sort to a covering index lookup in reverse order. Absolute timings vary with the machine and cache state; I record the plan shape rather than a single millisecond figure.

## Keeping the build in sync

I assembled `build/build.sql` from stages 00–07. If I edit a stage, I either regenerate the build or copy the change into it manually. If the two disagree, the modular run and the one-step build produce different databases.

I assembled `tests/all_tests.sql` from the test helpers and the five test files in the same way. `tests/run_all.sql` runs the modular files directly and is the better check when I am editing a stage.

## Privileges and authentication

The commands above assume a local `root` account, which is common in a lab. A shared or production account should have only what each job needs:

- Build/migration: `CREATE`, `ALTER`, `DROP`, `INDEX`, `REFERENCES`, `CREATE ROUTINE`, `ALTER ROUTINE`, `EXECUTE`, `CREATE VIEW`, `TRIGGER`.
- Application: `SELECT`, `INSERT`, `UPDATE`, `DELETE` on the tables, and `EXECUTE` on the procedures.
- Reporting: `SELECT` on the views or base tables.

With binary logging enabled, creating a stored function also requires `SET_USER_ID` (or the deprecated `SUPER`), and triggers are subject to the same trust rule; a missing privilege produces error 1419. A function that is not declared `DETERMINISTIC`, `NO SQL` or `READS SQL DATA` produces error 1418 unless `log_bin_trust_function_creators = 1`. The functions in this project satisfy the declaration rule but still need the privilege.

For a password, I prefer `mysql -p` or a login path created with `mysql_config_editor`. `MYSQL_PWD` is convenient for a local script but is inherited by child processes. I never commit a real password.
