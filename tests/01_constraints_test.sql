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
