-- ============================================================
-- tests/run_all.sql
-- CLI test runner. Run from the repository root:
--   mysql -u root --table -e "source tests/run_all.sql"
--
-- For MySQL Workbench, open tests/all_tests.sql instead: it is a
-- generated single-file concatenation of the same tests.
-- ============================================================

USE inventory_order_mgt;

SOURCE tests/sql/00_test_helpers.sql;
SOURCE tests/sql/01_constraints_test.sql;
SOURCE tests/sql/02_functions_test.sql;
SOURCE tests/sql/03_order_tests.sql;
SOURCE tests/sql/04_inventory_tests.sql;
SOURCE tests/sql/05_views_test.sql;
