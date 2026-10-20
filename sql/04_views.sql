-- ============================================================
-- 04_views.sql
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
