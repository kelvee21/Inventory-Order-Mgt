# SQL pipeline

Each numbered directory is one stage of the pipeline. Directory order is execution order.

| Stage | Directory | File | Purpose |
|---:|---|---|---|
| 0 | `00_reset/` | `00_reset.sql` | Drop lab objects and ensure the database exists |
| 1 | `01_schema/` | `01_schema.sql` | Tables, keys, constraints and data types |
| 2 | `02_indexes/` | `02_indexes.sql` | Secondary indexes for reporting access paths |
| 3 | `03_functions/` | `03_functions.sql` | Deterministic tier and discount functions |
| 4 | `04_views/` | `04_views.sql` | Stable reporting interfaces |
| 5 | `05_triggers/` | `05_triggers.sql` | Line pricing, stock movement and order totals |
| 6 | `06_procedures/` | `06_procedures.sql` | JSON order placement and replenishment |
| 7 | `07_seed/` | `07_seed_data.sql` | Deterministic customer, product and order fixtures |
| 8 | `08_reports/` | `08_reports.sql` | Ten analytical result sets |
| 9 | `09_quality/` | `09_data_quality_checks.sql` | Sixteen PASS/FAIL integrity checks |
| 10 | `10_benchmark/` | `10_performance_benchmark.sql` | `EXPLAIN ANALYZE` before/after index comparison |

## Build order

`00_reset` through `07_seed` are assembled into `build/build.sql`, which is committed for a one-step build. The reports, quality checks and benchmark are run separately against the seeded database.

```powershell
mysql -u root -e "source sql/build/build.sql"
mysql -u root --table -e "source sql/08_reports/08_reports.sql"
mysql -u root --table -e "source sql/09_quality/09_data_quality_checks.sql"
mysql -u root --table -e "source sql/10_benchmark/10_performance_benchmark.sql"
```

The stage files are the source of truth. If you change one, update `build/build.sql` so the assembled build stays in sync, or run the stages directly in numeric order against the database.
