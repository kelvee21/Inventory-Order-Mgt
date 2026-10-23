-- ============================================================
-- tests/run_all.sql
-- CLI test runner. Run from the tests directory:
--   mysql -u root inventory_order_mgt < run_all.sql
--
-- For MySQL Workbench, open tests/all_tests.sql instead: it is a
-- generated single-file concatenation of the same tests.
-- ============================================================

USE inventory_order_mgt;

SOURCE 00_test_helpers.sql;
SOURCE 01_constraints_test.sql;
SOURCE 02_functions_test.sql;
SOURCE 03_order_tests.sql;
SOURCE 04_inventory_tests.sql;
SOURCE 05_views_test.sql;
