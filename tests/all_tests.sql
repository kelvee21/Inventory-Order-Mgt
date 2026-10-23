-- ============================================================
-- Full test suite
-- Assembled from the modular test files in numeric order.
-- Edit the test files, then keep this file in sync.
-- ============================================================

-- >>> 00_test_helpers.sql >>>
-- ============================================================
-- tests/00_test_helpers.sql
-- Assertion helpers for the MySQL test suite.
--
-- These are created once. Test files only run DML and CALLs,
-- so their changes can be rolled back.
-- ============================================================

USE inventory_order_mgt;

DROP PROCEDURE IF EXISTS assert_true;

DELIMITER //
CREATE PROCEDURE assert_true(
  IN p_condition BOOLEAN,
  IN p_label VARCHAR(200)
)
BEGIN
  IF p_condition IS NULL OR p_condition = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = p_label;
  END IF;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS assert_raises;

DELIMITER //
CREATE PROCEDURE assert_raises(
  IN p_sql TEXT,
  IN p_expected_state CHAR(5),
  IN p_label VARCHAR(200)
)
BEGIN
  DECLARE v_state CHAR(5) DEFAULT '00000';
  DECLARE v_message TEXT;

  -- The handler is scoped to this inner block so the SIGNALs
  -- used to report a failed assertion are not swallowed.
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1
        v_state = RETURNED_SQLSTATE,
        v_message = MESSAGE_TEXT;
    END;

    SET @test_sql = p_sql;
    PREPARE test_stmt FROM @test_sql;
    EXECUTE test_stmt;
    DEALLOCATE PREPARE test_stmt;
  END;

  IF v_state = '00000' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Expected an error but the statement succeeded';
  ELSEIF v_state <> p_expected_state THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Statement failed with an unexpected SQLSTATE';
  END IF;
END //
DELIMITER ;

SELECT 'Test helpers created.' AS message;

-- >>> 01_constraints_test.sql >>>
-- ============================================================
-- tests/01_constraints_test.sql
-- Constraint and trigger rejection tests.
-- ============================================================

USE inventory_order_mgt;

START TRANSACTION;

CALL assert_raises(
  'INSERT INTO customers (full_name, email) VALUES (''Duplicate'', ''ama@example.com'')',
  '23000',
  'duplicate email is rejected'
);

CALL assert_raises(
  'INSERT INTO customers (full_name, email) VALUES (''Case duplicate'', ''AMA@EXAMPLE.COM'')',
  '23000',
  'case-only duplicate email is rejected'
);

CALL assert_raises(
  'INSERT INTO customers (full_name, email) VALUES (''Bad email'', ''not-an-email'')',
  'HY000',
  'invalid email format is rejected'
);

CALL assert_raises(
  'INSERT INTO customers (full_name, email) VALUES (''   '', ''blank@example.com'')',
  'HY000',
  'blank customer name is rejected'
);

CALL assert_raises(
  'INSERT INTO products (product_name, category, price) VALUES (''Bad price'', ''Test'', -1)',
  'HY000',
  'negative price is rejected'
);

CALL assert_raises(
  'INSERT INTO products (product_name, category, price, stock_quantity) VALUES (''Bad stock'', ''Test'', 1, -1)',
  'HY000',
  'negative stock is rejected'
);

CALL assert_raises(
  'INSERT INTO products (product_name, category, price, reorder_level) VALUES (''Bad reorder'', ''Test'', 1, -1)',
  'HY000',
  'negative reorder level is rejected'
);

CALL assert_raises(
  'INSERT INTO products (product_name, category, price) VALUES (''USB-C Cable'', ''Test'', 1)',
  '23000',
  'duplicate product name is rejected'
);

CALL assert_raises(
  'INSERT INTO orders (customer_id) VALUES (9999)',
  '23000',
  'order with unknown customer is rejected'
);

CALL assert_raises(
  'INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES (9999, 1, 1, 1, 1)',
  '23000',
  'order item with unknown order is rejected'
);

CALL assert_raises(
  'INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES (1, 1, 1, 1, 1)',
  '23000',
  'duplicate product line is rejected'
);

CALL assert_raises(
  'INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES (1, 1, 0, 1, 1)',
  '45000',
  'zero quantity is rejected by the trigger'
);

CALL assert_raises(
  'INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES (1, 999, 1, 1, 1)',
  '45000',
  'unknown product is rejected by the trigger'
);

CALL assert_raises(
  'UPDATE order_items SET discount_rate = 1.50 WHERE order_id = 1 AND product_id = 1',
  'HY000',
  'discount above 1 is rejected'
);

CALL assert_raises(
  'UPDATE products SET stock_quantity = -1 WHERE product_id = 1',
  'HY000',
  'negative stock update is rejected'
);

CALL assert_raises(
  'INSERT INTO inventory_logs (product_id, change_quantity, reason) VALUES (1, 0, ''adjustment'')',
  'HY000',
  'zero inventory change is rejected'
);

CALL assert_raises(
  'INSERT INTO inventory_logs (product_id, change_quantity, reason) VALUES (1, 1, ''bogus'')',
  'HY000',
  'invalid inventory reason is rejected'
);

SELECT '01_constraints_test passed' AS result;

ROLLBACK;

-- >>> 02_functions_test.sql >>>
-- ============================================================
-- tests/02_functions_test.sql
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

-- >>> 03_order_tests.sql >>>
-- ============================================================
-- tests/03_order_tests.sql
-- Order placement, trigger automation and failure handling.
-- ============================================================

USE inventory_order_mgt;

START TRANSACTION;

INSERT INTO customers (customer_id, full_name, email)
VALUES (100, 'Test Customer', 'test.customer@example.com');

INSERT INTO products
  (product_id, product_name, category, price, stock_quantity, reorder_level)
VALUES
  (100, 'Test Cable',   'Test', 10.00, 100, 5),
  (101, 'Test Monitor', 'Test', 20.00,  50, 5);

SET @items = JSON_ARRAY(
  JSON_OBJECT('product_id', 100, 'quantity', 5),
  JSON_OBJECT('product_id', 101, 'quantity', 10)
);

CALL place_order(100, @items, '2026-10-21', @order_id);

CALL assert_true(@order_id IS NOT NULL, 'order id is returned');
CALL assert_true(
  (SELECT COUNT(*) FROM orders WHERE order_id = @order_id AND total_amount = 227.50) = 1,
  'order total is 227.50'
);
CALL assert_true(
  (SELECT COUNT(*) FROM order_items WHERE order_id = @order_id) = 2,
  'order has two lines'
);
CALL assert_true(
  (SELECT COUNT(*) FROM order_items
    WHERE order_id = @order_id
      AND product_id = 100
      AND unit_price = 10.00
      AND discount_rate = 0.05
      AND line_total = 47.50) = 1,
  'five cables get 5 percent discount and total 47.50'
);
CALL assert_true(
  (SELECT COUNT(*) FROM order_items
    WHERE order_id = @order_id
      AND product_id = 101
      AND unit_price = 20.00
      AND discount_rate = 0.10
      AND line_total = 180.00) = 1,
  'ten monitors get 10 percent discount and total 180.00'
);
CALL assert_true(
  (SELECT stock_quantity FROM products WHERE product_id = 100) = 95,
  'cable stock is deducted'
);
CALL assert_true(
  (SELECT stock_quantity FROM products WHERE product_id = 101) = 40,
  'monitor stock is deducted'
);
CALL assert_true(
  (SELECT COUNT(*) FROM inventory_logs WHERE order_id = @order_id AND reason = 'order') = 2,
  'one sale log per line'
);
CALL assert_true(
  (SELECT SUM(change_quantity) FROM inventory_logs WHERE order_id = @order_id) = -15,
  'sale logs total -15 units'
);

-- The order line must keep the price at the time of sale.
UPDATE products SET price = 99.00 WHERE product_id = 100;
CALL assert_true(
  (SELECT unit_price FROM order_items WHERE order_id = @order_id AND product_id = 100) = 10.00,
  'sale price remains a historical snapshot'
);

-- A caller-supplied price must be ignored by the BEFORE trigger.
INSERT INTO orders (order_id, customer_id, order_date, total_amount)
VALUES (1001, 100, '2026-10-21', 0.00);

INSERT INTO order_items
  (order_id, product_id, quantity, unit_price, discount_rate, line_total)
VALUES
  (1001, 100, 2, 999.00, 0.50, 999.00);

CALL assert_true(
  (SELECT unit_price FROM order_items WHERE order_id = 1001 AND product_id = 100) = 99.00,
  'trigger replaces a caller-supplied unit price'
);
CALL assert_true(
  (SELECT total_amount FROM orders WHERE order_id = 1001) = 198.00,
  'trigger recalculates the order total'
);

SET @orders_before = (SELECT COUNT(*) FROM orders WHERE customer_id = 100);

CALL assert_raises(
  'CALL place_order(100, JSON_ARRAY(JSON_OBJECT(''product_id'', 100, ''quantity'', 9999)), ''2026-10-21'', @bad_order)',
  '45000',
  'oversell is rejected'
);

CALL assert_true(
  (SELECT COUNT(*) FROM orders WHERE customer_id = 100) = @orders_before,
  'failed oversell leaves no order row'
);

CALL assert_raises(
  'CALL place_order(9999, JSON_ARRAY(JSON_OBJECT(''product_id'', 100, ''quantity'', 1)), ''2026-10-21'', @bad_order)',
  '45000',
  'unknown customer is rejected'
);

CALL assert_raises(
  'CALL place_order(100, JSON_ARRAY(JSON_OBJECT(''product_id'', 999, ''quantity'', 1)), ''2026-10-21'', @bad_order)',
  '45000',
  'unknown product is rejected'
);

CALL assert_raises(
  'CALL place_order(100, JSON_ARRAY(), ''2026-10-21'', @bad_order)',
  '45000',
  'empty item list is rejected'
);

CALL assert_raises(
  'CALL place_order(100, JSON_OBJECT(''product_id'', 100, ''quantity'', 1), ''2026-10-21'', @bad_order)',
  '45000',
  'non-array item input is rejected'
);

CALL assert_raises(
  'CALL place_order(100, JSON_ARRAY(JSON_OBJECT(''product_id'', 100, ''quantity'', 1), JSON_OBJECT(''product_id'', 100, ''quantity'', 2)), ''2026-10-21'', @bad_order)',
  '45000',
  'duplicate product ids are rejected'
);

CALL assert_raises(
  'CALL place_order(100, JSON_ARRAY(JSON_OBJECT(''product_id'', 100, ''quantity'', 0)), ''2026-10-21'', @bad_order)',
  '45000',
  'zero quantity is rejected'
);

CALL place_order(
  100,
  JSON_ARRAY(JSON_OBJECT('product_id', 101, 'quantity', 1)),
  NULL,
  @order_id_2
);

CALL assert_true(
  (SELECT order_date FROM orders WHERE order_id = @order_id_2) = CURRENT_DATE,
  'null order date defaults to today'
);

SELECT '03_order_tests passed' AS result;

ROLLBACK;

-- >>> 04_inventory_tests.sql >>>
-- ============================================================
-- tests/04_inventory_tests.sql
-- Restock, idempotence and reconciliation tests.
-- ============================================================

USE inventory_order_mgt;

START TRANSACTION;

-- Seed state has three low-stock products.
CALL assert_true(
  (SELECT COUNT(*) FROM v_low_stock) = 3,
  'seed has three low-stock products'
);

INSERT INTO products
  (product_id, product_name, category, price, stock_quantity, reorder_level)
VALUES
  (200, 'Restock Test A', 'Test', 1.00,  0, 5),
  (201, 'Restock Test B', 'Test', 1.00, 10, 5);

-- Product 201 starts with stock, so give it an opening log.
INSERT INTO inventory_logs (product_id, change_quantity, reason)
VALUES (201, 10, 'opening');

CALL assert_true(
  (SELECT COUNT(*) FROM v_low_stock) = 4,
  'the new zero-stock product is low'
);

CALL restock_low_products();

CALL assert_true(
  (SELECT stock_quantity FROM products WHERE product_id = 200) = 10,
  'restock tops product 200 up to twice its reorder level'
);
CALL assert_true(
  (SELECT stock_quantity FROM products WHERE product_id = 201) = 10,
  'restock leaves a non-low product unchanged'
);
CALL assert_true(
  (SELECT COUNT(*) FROM inventory_logs WHERE product_id = 200 AND reason = 'restock') = 1,
  'restock writes one log for product 200'
);
CALL assert_true(
  (SELECT change_quantity FROM inventory_logs WHERE product_id = 200 AND reason = 'restock') = 10,
  'restock log has the correct positive quantity'
);
CALL assert_true(
  (SELECT COUNT(*) FROM inventory_logs WHERE product_id = 201 AND reason = 'restock') = 0,
  'non-low product gets no restock log'
);
CALL assert_true(
  (SELECT COUNT(*) FROM v_low_stock) = 0,
  'low-stock view is empty after restock'
);

CALL restock_low_products();

CALL assert_true(
  (SELECT stock_quantity FROM products WHERE product_id = 200) = 10,
  'second restock does not add stock again'
);
CALL assert_true(
  (SELECT COUNT(*) FROM inventory_logs WHERE product_id = 200 AND reason = 'restock') = 1,
  'second restock is idempotent'
);
CALL assert_true(
  (SELECT COUNT(*) FROM inventory_logs WHERE reason = 'restock' AND change_quantity <= 0) = 0,
  'all restock logs are positive'
);

CALL assert_true(
  (SELECT COUNT(*) FROM (
    SELECT p.product_id
    FROM products AS p
    LEFT JOIN inventory_logs AS il
      ON il.product_id = p.product_id
    GROUP BY p.product_id, p.stock_quantity
    HAVING p.stock_quantity <> COALESCE(SUM(il.change_quantity), 0)
  ) AS mismatches) = 0,
  'stock still reconciles to inventory logs after restock'
);

SELECT '04_inventory_tests passed' AS result;

ROLLBACK;

-- >>> 05_views_test.sql >>>
-- ============================================================
-- tests/05_views_test.sql
-- Expected rows and values for the reporting views.
-- ============================================================

USE inventory_order_mgt;

START TRANSACTION;

CALL assert_true(
  (SELECT COUNT(*) FROM v_order_summary) = 5,
  'order summary has five seed orders'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_order_summary
    WHERE order_id = 1
      AND customer_name = 'Ama Mensah'
      AND total_amount = 50.50
      AND item_count = 4) = 1,
  'order 1 summary is correct'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_order_summary
    WHERE order_id = 4
      AND total_amount = 126.50
      AND item_count = 12) = 1,
  'order 4 summary and discount total are correct'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_low_stock) = 3,
  'low-stock view has three products'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_low_stock WHERE product_id IN (2, 4, 5)) = 3,
  'low-stock view contains mouse, monitor and stand'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_customer_spend
    WHERE customer_id = 1
      AND total_spend = 548.50
      AND tier = 'Gold') = 1,
  'Ama is Gold'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_customer_spend
    WHERE customer_id = 2
      AND total_spend = 355.99
      AND tier = 'Silver') = 1,
  'Kofi is Silver'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_customer_spend
    WHERE customer_id = 3
      AND total_spend = 126.50
      AND tier = 'Bronze') = 1,
  'Esi is Bronze'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_customer_spend
    WHERE customer_id = 4
      AND total_spend = 0.00
      AND tier = 'Bronze') = 1,
  'Yaw is Bronze with zero spend'
);

CALL assert_true(
  (SELECT ROUND(SUM(total_spend), 2) FROM v_customer_spend) = 1030.99,
  'customer spend totals 1030.99'
);

SELECT '05_views_test passed' AS result;

ROLLBACK;

