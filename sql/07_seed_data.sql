-- ============================================================
-- 07_seed_data.sql
-- Deterministic sample data for demos, reports and tests.
--
-- Orders are loaded through place_order, not inserted directly,
-- so the triggers deduct stock, calculate discounts/totals and
-- write the inventory logs.
-- ============================================================

USE inventory_order_mgt;

START TRANSACTION;

INSERT INTO customers (customer_id, full_name, email, phone) VALUES
  (1, 'Ama Mensah',   'ama@example.com',  '0244000001'),
  (2, 'Kofi Boateng', 'kofi@example.com', NULL),
  (3, 'Esi Owusu',    'esi@example.com',  '0201000003'),
  (4, 'Yaw Darko',    'yaw@example.com',  '0555000004');

INSERT INTO products
  (product_id, product_name, category, price, stock_quantity, reorder_level)
VALUES
  (1, 'USB-C Cable',         'Accessories',   8.50, 120, 30),
  (2, 'Wireless Mouse',      'Accessories',  25.00,  15, 20),
  (3, 'Mechanical Keyboard', 'Peripherals',  89.99,  40, 10),
  (4, '27in Monitor',        'Displays',    249.00,   5,  8),
  (5, 'Laptop Stand',        'Accessories',  39.00,   0,  5);

-- Opening balances make SUM(change_quantity) reconcile to stock.
-- Product 5 starts at zero, so it intentionally has no zero-value log.
INSERT INTO inventory_logs (product_id, order_id, change_quantity, reason) VALUES
  (1, NULL, 120, 'opening'),
  (2, NULL,  15, 'opening'),
  (3, NULL,  40, 'opening'),
  (4, NULL,   5, 'opening');

-- Order 1: Ama, 3 cables + 1 mouse = 50.50
SET @items = JSON_ARRAY(
  JSON_OBJECT('product_id', 1, 'quantity', 3),
  JSON_OBJECT('product_id', 2, 'quantity', 1)
);
CALL place_order(1, @items, '2026-09-01', @order_1);

-- Order 2: Kofi, 1 keyboard + 1 monitor = 338.99
SET @items = JSON_ARRAY(
  JSON_OBJECT('product_id', 3, 'quantity', 1),
  JSON_OBJECT('product_id', 4, 'quantity', 1)
);
CALL place_order(2, @items, '2026-09-03', @order_2);

-- Order 3: Ama, 2 monitors = 498.00
SET @items = JSON_ARRAY(
  JSON_OBJECT('product_id', 4, 'quantity', 2)
);
CALL place_order(1, @items, '2026-09-10', @order_3);

-- Order 4: Esi, 10 cables (10% discount) + 2 mice = 126.50
SET @items = JSON_ARRAY(
  JSON_OBJECT('product_id', 1, 'quantity', 10),
  JSON_OBJECT('product_id', 2, 'quantity', 2)
);
CALL place_order(3, @items, '2026-09-15', @order_4);

-- Order 5: Kofi, 2 cables = 17.00
SET @items = JSON_ARRAY(
  JSON_OBJECT('product_id', 1, 'quantity', 2)
);
CALL place_order(2, @items, '2026-09-28', @order_5);

COMMIT;

SELECT 'Seed data loaded.' AS message;
