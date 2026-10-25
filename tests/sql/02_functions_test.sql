-- ============================================================
-- tests/sql/02_functions_test.sql
-- Boundary tests for tier and bulk-discount functions.
-- ============================================================

USE inventory_order_mgt;

START TRANSACTION;

CALL assert_true(customer_tier(0)      = 'Bronze', 'tier 0 is Bronze');
CALL assert_true(customer_tier(199.99) = 'Bronze', 'tier 199.99 is Bronze');
CALL assert_true(customer_tier(200)    = 'Silver', 'tier 200 is Silver');
CALL assert_true(customer_tier(499.99) = 'Silver', 'tier 499.99 is Silver');
CALL assert_true(customer_tier(500)    = 'Gold',   'tier 500 is Gold');
CALL assert_true(customer_tier(1000)   = 'Gold',   'tier 1000 is Gold');

CALL assert_true(bulk_discount_rate(0)   = 0.00, 'quantity 0 has no discount');
CALL assert_true(bulk_discount_rate(4)   = 0.00, 'quantity 4 has no discount');
CALL assert_true(bulk_discount_rate(5)   = 0.05, 'quantity 5 gets 5 percent');
CALL assert_true(bulk_discount_rate(9)   = 0.05, 'quantity 9 gets 5 percent');
CALL assert_true(bulk_discount_rate(10)  = 0.10, 'quantity 10 gets 10 percent');
CALL assert_true(bulk_discount_rate(100) = 0.10, 'quantity 100 gets 10 percent');

SELECT '02_functions_test passed' AS result;

ROLLBACK;
