-- ============================================================
-- tests/sql/04_inventory_tests.sql
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
