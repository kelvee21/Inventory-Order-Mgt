-- ============================================================
-- Build: schema, automation and seed data
-- Assembled from the numbered stage files in execution order.
-- Edit the stage files, then keep this file in sync.
-- ============================================================

-- >>> sql/00_reset/00_reset.sql >>>
-- ============================================================
-- sql/00_reset/00_reset.sql
-- Rebuild the inventory_order_mgt database from a clean state.
--
-- Safe for a local lab database: it drops the lab's views,
-- tables, procedures and functions, but does not drop the
-- database itself.
-- ============================================================

CREATE DATABASE IF NOT EXISTS inventory_order_mgt
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE inventory_order_mgt;

-- Views depend on tables and functions, so remove them first.
DROP VIEW IF EXISTS v_customer_spend;
DROP VIEW IF EXISTS v_low_stock;
DROP VIEW IF EXISTS v_order_summary;

-- Dropping the tables also removes their triggers.
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS inventory_logs;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;
SET FOREIGN_KEY_CHECKS = 1;

DROP PROCEDURE IF EXISTS place_order;
DROP PROCEDURE IF EXISTS restock_low_products;

DROP FUNCTION IF EXISTS customer_tier;
DROP FUNCTION IF EXISTS bulk_discount_rate;

SELECT 'Database reset complete.' AS message;

-- >>> sql/01_schema/01_schema.sql >>>
-- ============================================================
-- sql/01_schema/01_schema.sql
-- Core tables, keys, checks and relationships.
--
-- MySQL 8.0.16+ is required because CHECK constraints are
-- enforced from that version onwards.
-- ============================================================

USE inventory_order_mgt;

-- ------------------------------------------------------------
-- Customers
-- ------------------------------------------------------------
CREATE TABLE customers (
  customer_id INT NOT NULL AUTO_INCREMENT,
  full_name   VARCHAR(100) NOT NULL,
  email       VARCHAR(255) NOT NULL,
  phone       VARCHAR(20) NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (customer_id),
  UNIQUE KEY uq_customers_email (email),
  CONSTRAINT chk_customers_name
    CHECK (TRIM(full_name) <> ''),
  CONSTRAINT chk_customers_email
    CHECK (email LIKE '%_@_%._%')
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci;

-- ------------------------------------------------------------
-- Products
-- ------------------------------------------------------------
CREATE TABLE products (
  product_id     INT NOT NULL AUTO_INCREMENT,
  product_name   VARCHAR(100) NOT NULL,
  category       VARCHAR(50) NOT NULL,
  price          DECIMAL(10,2) NOT NULL,
  stock_quantity INT NOT NULL DEFAULT 0,
  reorder_level  INT NOT NULL DEFAULT 10,
  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (product_id),
  UNIQUE KEY uq_products_name (product_name),
  CONSTRAINT chk_products_name
    CHECK (TRIM(product_name) <> ''),
  CONSTRAINT chk_products_category
    CHECK (TRIM(category) <> ''),
  CONSTRAINT chk_products_price
    CHECK (price >= 0),
  CONSTRAINT chk_products_stock
    CHECK (stock_quantity >= 0),
  CONSTRAINT chk_products_reorder
    CHECK (reorder_level >= 0)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci;

-- ------------------------------------------------------------
-- Orders
-- ------------------------------------------------------------
CREATE TABLE orders (
  order_id     INT NOT NULL AUTO_INCREMENT,
  customer_id  INT NOT NULL,
  order_date   DATE NOT NULL DEFAULT (CURRENT_DATE),
  total_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (order_id),
  -- Supports customer history and the customer foreign key.
  KEY idx_orders_customer_date (customer_id, order_date),
  CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id)
    REFERENCES customers (customer_id)
    ON DELETE RESTRICT,
  CONSTRAINT chk_orders_total
    CHECK (total_amount >= 0)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci;

-- ------------------------------------------------------------
-- Order items
--
-- unit_price is the price on the day of sale, not a copy of
-- products.price. The trigger fills it from the catalogue.
-- ------------------------------------------------------------
CREATE TABLE order_items (
  order_item_id INT NOT NULL AUTO_INCREMENT,
  order_id      INT NOT NULL,
  product_id    INT NOT NULL,
  quantity      INT NOT NULL,
  unit_price    DECIMAL(10,2) NOT NULL,
  discount_rate DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  line_total    DECIMAL(12,2) NOT NULL,
  PRIMARY KEY (order_item_id),
  -- One line per product per order; also covers the order_id FK.
  UNIQUE KEY uq_order_items_order_product (order_id, product_id),
  -- Supports product sales joins and the product FK.
  KEY idx_order_items_product (product_id),
  CONSTRAINT fk_order_items_order
    FOREIGN KEY (order_id)
    REFERENCES orders (order_id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_order_items_product
    FOREIGN KEY (product_id)
    REFERENCES products (product_id)
    ON DELETE RESTRICT,
  CONSTRAINT chk_order_items_quantity
    CHECK (quantity > 0),
  CONSTRAINT chk_order_items_price
    CHECK (unit_price >= 0),
  CONSTRAINT chk_order_items_discount
    CHECK (discount_rate BETWEEN 0 AND 1),
  CONSTRAINT chk_order_items_total
    CHECK (line_total >= 0)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci;

-- ------------------------------------------------------------
-- Inventory logs
--
-- order_id is nullable because opening balances and restocks
-- are not tied to an order. change_quantity is signed:
-- negative for sales, positive for restocks and adjustments.
-- ------------------------------------------------------------
CREATE TABLE inventory_logs (
  log_id          INT NOT NULL AUTO_INCREMENT,
  product_id      INT NOT NULL,
  order_id        INT NULL,
  change_quantity INT NOT NULL,
  reason          VARCHAR(20) NOT NULL,
  changed_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (log_id),
  -- Per-product audit history and the product FK.
  KEY idx_inventory_logs_product_time (product_id, changed_at),
  -- Audit by order and the order FK.
  KEY idx_inventory_logs_order (order_id),
  CONSTRAINT fk_inventory_logs_product
    FOREIGN KEY (product_id)
    REFERENCES products (product_id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_inventory_logs_order
    FOREIGN KEY (order_id)
    REFERENCES orders (order_id)
    ON DELETE RESTRICT,
  CONSTRAINT chk_inventory_logs_change
    CHECK (change_quantity <> 0),
  CONSTRAINT chk_inventory_logs_reason
    CHECK (reason IN ('opening', 'order', 'restock', 'adjustment'))
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci;

SELECT 'Schema created.' AS message;

-- >>> sql/02_indexes/02_indexes.sql >>>
-- ============================================================
-- sql/02_indexes/02_indexes.sql
-- Additional indexes that are not needed by foreign keys.
--
-- MySQL creates an index automatically for an unindexed FK
-- column. All FK-supporting indexes are declared inline in
-- 01_schema.sql so this file does not create duplicates.
-- ============================================================

USE inventory_order_mgt;

-- Date-range and daily/monthly sales reports.
CREATE INDEX idx_orders_order_date
  ON orders (order_date);

SELECT 'Additional indexes created.' AS message;

-- >>> sql/03_functions/03_functions.sql >>>
-- ============================================================
-- sql/03_functions/03_functions.sql
-- Deterministic business rules kept in one place.
-- ============================================================

USE inventory_order_mgt;

DROP FUNCTION IF EXISTS customer_tier;

DELIMITER //
CREATE FUNCTION customer_tier(p_spend DECIMAL(12,2))
RETURNS VARCHAR(10)
DETERMINISTIC
NO SQL
BEGIN
  RETURN CASE
    WHEN p_spend >= 500 THEN 'Gold'
    WHEN p_spend >= 200 THEN 'Silver'
    ELSE 'Bronze'
  END;
END //
DELIMITER ;

DROP FUNCTION IF EXISTS bulk_discount_rate;

DELIMITER //
CREATE FUNCTION bulk_discount_rate(p_quantity INT)
RETURNS DECIMAL(4,2)
DETERMINISTIC
NO SQL
BEGIN
  RETURN CASE
    WHEN p_quantity >= 10 THEN 0.10
    WHEN p_quantity >= 5  THEN 0.05
    ELSE 0.00
  END;
END //
DELIMITER ;

SELECT 'Functions created.' AS message;

-- >>> sql/04_views/04_views.sql >>>
-- ============================================================
-- sql/04_views/04_views.sql
-- Stable read interfaces for reports and analysts.
-- ============================================================

USE inventory_order_mgt;

-- One row per order with the customer and total units.
CREATE OR REPLACE VIEW v_order_summary AS
SELECT
  o.order_id,
  o.customer_id,
  c.full_name AS customer_name,
  o.order_date,
  o.total_amount,
  COALESCE(SUM(oi.quantity), 0) AS item_count
FROM orders AS o
JOIN customers AS c
  ON c.customer_id = o.customer_id
LEFT JOIN order_items AS oi
  ON oi.order_id = o.order_id
GROUP BY
  o.order_id,
  o.customer_id,
  c.full_name,
  o.order_date,
  o.total_amount;

-- Products at or below their reorder point? Strictly below,
-- which is how the lab defines "low on stock".
CREATE OR REPLACE VIEW v_low_stock AS
SELECT
  product_id,
  product_name,
  category,
  stock_quantity,
  reorder_level,
  reorder_level - stock_quantity AS shortfall
FROM products
WHERE stock_quantity < reorder_level;

-- Customer lifetime spend and tier. LEFT JOIN keeps customers
-- with no orders in the report.
CREATE OR REPLACE VIEW v_customer_spend AS
SELECT
  c.customer_id,
  c.full_name,
  COALESCE(SUM(o.total_amount), 0.00) AS total_spend,
  customer_tier(COALESCE(SUM(o.total_amount), 0.00)) AS tier
FROM customers AS c
LEFT JOIN orders AS o
  ON o.customer_id = c.customer_id
GROUP BY
  c.customer_id,
  c.full_name;

SELECT 'Views created.' AS message;

-- >>> sql/05_triggers/05_triggers.sql >>>
-- ============================================================
-- sql/05_triggers/05_triggers.sql
-- Order-line automation:
--   * snapshot the catalogue price
--   * apply the quantity discount
--   * calculate the line total
--   * deduct stock, write an inventory log and update the order total
--
-- The BEFORE trigger locks the product row before reading its
-- price. The AFTER trigger locks the same row again and performs
-- the authoritative stock check.
-- ============================================================

USE inventory_order_mgt;

DROP TRIGGER IF EXISTS trg_order_items_before_insert;

DELIMITER //
CREATE TRIGGER trg_order_items_before_insert
BEFORE INSERT ON order_items
FOR EACH ROW
BEGIN
  DECLARE v_price DECIMAL(10,2);
  DECLARE v_msg VARCHAR(255);
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_price = NULL;

  IF NEW.quantity IS NULL OR NEW.quantity <= 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Order quantity must be greater than zero';
  END IF;

  SELECT price
    INTO v_price
    FROM products
   WHERE product_id = NEW.product_id
   FOR UPDATE;

  IF v_price IS NULL THEN
    SET v_msg = CONCAT('Unknown product: ', NEW.product_id);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;

  -- Callers cannot inject a different price or discount.
  SET NEW.unit_price = v_price;
  SET NEW.discount_rate = bulk_discount_rate(NEW.quantity);
  SET NEW.line_total = ROUND(
    NEW.quantity * v_price * (1 - NEW.discount_rate),
    2
  );
END //
DELIMITER ;

DROP TRIGGER IF EXISTS trg_order_items_after_insert;

DELIMITER //
CREATE TRIGGER trg_order_items_after_insert
AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
  DECLARE v_stock INT;
  DECLARE v_msg VARCHAR(255);
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_stock = NULL;

  SELECT stock_quantity
    INTO v_stock
    FROM products
   WHERE product_id = NEW.product_id
   FOR UPDATE;

  IF v_stock IS NULL THEN
    SET v_msg = CONCAT('Unknown product: ', NEW.product_id);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;

  IF v_stock < NEW.quantity THEN
    SET v_msg = CONCAT(
      'Not enough stock for product ', NEW.product_id,
      ' (have ', v_stock, ', need ', NEW.quantity, ')'
    );
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;

  UPDATE products
     SET stock_quantity = stock_quantity - NEW.quantity
   WHERE product_id = NEW.product_id;

  INSERT INTO inventory_logs
    (product_id, order_id, change_quantity, reason)
  VALUES
    (NEW.product_id, NEW.order_id, -NEW.quantity, 'order');

  UPDATE orders
     SET total_amount = total_amount + NEW.line_total
   WHERE order_id = NEW.order_id;
END //
DELIMITER ;

SELECT 'Triggers created.' AS message;

-- >>> sql/06_procedures/06_procedures.sql >>>
-- ============================================================
-- sql/06_procedures/06_procedures.sql
-- place_order           - create an order with one or more JSON items
-- restock_low_products  - top up every product below its reorder level
--
-- Both procedures leave transaction control to the caller.
-- Use:
--   START TRANSACTION;
--   CALL ...;
--   COMMIT;
-- and ROLLBACK on error.
-- ============================================================

USE inventory_order_mgt;

DROP PROCEDURE IF EXISTS place_order;

DELIMITER //
CREATE PROCEDURE place_order(
  IN  p_customer_id INT,
  IN  p_items JSON,
  IN  p_order_date DATE,
  OUT p_order_id INT
)
BEGIN
  DECLARE v_count INT DEFAULT 0;
  DECLARE v_bad INT DEFAULT 0;
  DECLARE v_msg VARCHAR(255);

  IF p_customer_id IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Customer id is required';
  END IF;

  IF p_items IS NULL
     OR JSON_VALID(p_items) = 0
     OR JSON_TYPE(p_items) <> 'ARRAY'
     OR JSON_LENGTH(p_items) = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Items must be a non-empty JSON array';
  END IF;

  -- Every item must carry a product id and a positive quantity.
  SELECT COUNT(*)
    INTO v_bad
    FROM JSON_TABLE(
      p_items,
      '$[*]' COLUMNS (
        product_id INT PATH '$.product_id',
        quantity   INT PATH '$.quantity'
      )
    ) AS jt
   WHERE jt.product_id IS NULL
      OR jt.quantity IS NULL
      OR jt.quantity <= 0;

  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Each item needs a product_id and a quantity greater than zero';
  END IF;

  -- One line per product: increase the quantity instead of repeating it.
  SELECT COUNT(*)
    INTO v_bad
    FROM (
      SELECT jt.product_id
        FROM JSON_TABLE(
          p_items,
          '$[*]' COLUMNS (
            product_id INT PATH '$.product_id'
          )
        ) AS jt
       GROUP BY jt.product_id
      HAVING COUNT(*) > 1
    ) AS duplicates;

  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Duplicate product in order items';
  END IF;

  SELECT COUNT(*)
    INTO v_count
    FROM customers
   WHERE customer_id = p_customer_id;

  IF v_count = 0 THEN
    SET v_msg = CONCAT('Unknown customer: ', p_customer_id);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;

  SELECT COUNT(*)
    INTO v_bad
    FROM JSON_TABLE(
      p_items,
      '$[*]' COLUMNS (
        product_id INT PATH '$.product_id'
      )
    ) AS jt
    LEFT JOIN products AS p
      ON p.product_id = jt.product_id
   WHERE p.product_id IS NULL;

  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'One or more products do not exist';
  END IF;

  -- Friendly pre-check. The AFTER trigger repeats the check under
  -- a row lock, which is the authoritative concurrency guard.
  SELECT COUNT(*)
    INTO v_bad
    FROM JSON_TABLE(
      p_items,
      '$[*]' COLUMNS (
        product_id INT PATH '$.product_id',
        quantity   INT PATH '$.quantity'
      )
    ) AS jt
    JOIN products AS p
      ON p.product_id = jt.product_id
   WHERE p.stock_quantity < jt.quantity;

  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Insufficient stock for one or more products';
  END IF;

  INSERT INTO orders (customer_id, order_date)
  VALUES (p_customer_id, COALESCE(p_order_date, CURRENT_DATE));

  SET p_order_id = LAST_INSERT_ID();

  -- Product-id order keeps lock acquisition consistent when
  -- concurrent orders contain the same products.
  INSERT INTO order_items (order_id, product_id, quantity)
  SELECT
    p_order_id,
    jt.product_id,
    jt.quantity
  FROM JSON_TABLE(
    p_items,
    '$[*]' COLUMNS (
      product_id INT PATH '$.product_id',
      quantity   INT PATH '$.quantity'
    )
  ) AS jt
  ORDER BY jt.product_id;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS restock_low_products;

DELIMITER //
CREATE PROCEDURE restock_low_products()
BEGIN
  DECLARE v_done INT DEFAULT 0;
  DECLARE v_product_id INT;
  DECLARE v_stock INT;
  DECLARE v_reorder INT;
  DECLARE v_add_qty INT;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

  WHILE v_done = 0 DO
    SET v_product_id = NULL;

    SELECT
      product_id,
      stock_quantity,
      reorder_level
    INTO
      v_product_id,
      v_stock,
      v_reorder
    FROM products
    WHERE stock_quantity < reorder_level
    ORDER BY product_id
    LIMIT 1
    FOR UPDATE;

    IF v_product_id IS NULL THEN
      SET v_done = 1;
    ELSE
      SET v_add_qty = (v_reorder * 2) - v_stock;

      UPDATE products
         SET stock_quantity = stock_quantity + v_add_qty
       WHERE product_id = v_product_id;

      INSERT INTO inventory_logs
        (product_id, change_quantity, reason)
      VALUES
        (v_product_id, v_add_qty, 'restock');
    END IF;
  END WHILE;
END //
DELIMITER ;

SELECT 'Procedures created.' AS message;

-- >>> sql/07_seed/07_seed_data.sql >>>
-- ============================================================
-- sql/07_seed/07_seed_data.sql
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

