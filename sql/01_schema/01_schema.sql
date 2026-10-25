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
