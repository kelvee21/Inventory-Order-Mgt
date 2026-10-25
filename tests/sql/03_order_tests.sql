-- ============================================================
-- tests/sql/03_order_tests.sql
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
