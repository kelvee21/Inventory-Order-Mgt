-- ============================================================
-- 08_reports.sql
-- Business reports for the lab deliverables.
--
-- Run after sql/build.sql. The seed data produces five orders
-- in September 2026 and three low-stock products.
-- ============================================================

USE inventory_order_mgt;

-- ------------------------------------------------------------
-- 1. Customer order summary
--    One row per customer, including customers with no orders.
-- ------------------------------------------------------------
SELECT
  c.customer_id,
  c.full_name AS customer_name,
  COUNT(o.order_id) AS order_count,
  COALESCE(SUM(o.total_amount), 0.00) AS total_spend,
  ROUND(COALESCE(AVG(o.total_amount), 0.00), 2) AS avg_order_value,
  COALESCE(SUM(oi.units), 0) AS items_bought
FROM customers AS c
LEFT JOIN orders AS o
  ON o.customer_id = c.customer_id
LEFT JOIN (
  SELECT order_id, SUM(quantity) AS units
  FROM order_items
  GROUP BY order_id
) AS oi
  ON oi.order_id = o.order_id
GROUP BY c.customer_id, c.full_name
ORDER BY total_spend DESC, c.customer_id;

-- ------------------------------------------------------------
-- 2. Order detail per customer
-- ------------------------------------------------------------
SELECT
  order_id,
  customer_id,
  customer_name,
  order_date,
  total_amount,
  item_count
FROM v_order_summary
ORDER BY customer_id, order_date, order_id;

-- ------------------------------------------------------------
-- 3. Low-stock report and suggested replenishment
-- ------------------------------------------------------------
SELECT
  product_id,
  product_name,
  category,
  stock_quantity,
  reorder_level,
  shortfall,
  (reorder_level * 2) - stock_quantity AS suggested_restock
FROM v_low_stock
ORDER BY shortfall DESC, product_name;

-- ------------------------------------------------------------
-- 4. Customer tiers
-- ------------------------------------------------------------
SELECT
  tier,
  COUNT(*) AS customer_count,
  ROUND(SUM(total_spend), 2) AS total_spend,
  ROUND(AVG(total_spend), 2) AS avg_spend
FROM v_customer_spend
GROUP BY tier
ORDER BY CASE tier
           WHEN 'Gold'   THEN 1
           WHEN 'Silver' THEN 2
           ELSE 3
         END;

-- ------------------------------------------------------------
-- 5. Product sales
--    gross_revenue uses the snapshot unit price;
--    discount_amount is the value given away by bulk pricing.
-- ------------------------------------------------------------
SELECT
  p.product_id,
  p.product_name,
  p.category,
  SUM(oi.quantity) AS units_sold,
  COUNT(DISTINCT oi.order_id) AS order_count,
  ROUND(SUM(oi.quantity * oi.unit_price), 2) AS gross_revenue,
  ROUND(SUM((oi.quantity * oi.unit_price) - oi.line_total), 2) AS discount_amount,
  ROUND(SUM(oi.line_total), 2) AS net_revenue
FROM order_items AS oi
JOIN products AS p
  ON p.product_id = oi.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY net_revenue DESC, p.product_id;

-- ------------------------------------------------------------
-- 6. Inventory movement and audit reconciliation
-- ------------------------------------------------------------
SELECT
  p.product_id,
  p.product_name,
  p.stock_quantity AS current_stock,
  COALESCE(SUM(CASE WHEN il.reason = 'opening'    THEN il.change_quantity ELSE 0 END), 0) AS opening_qty,
  COALESCE(SUM(CASE WHEN il.reason = 'order'      THEN il.change_quantity ELSE 0 END), 0) AS sold_qty,
  COALESCE(SUM(CASE WHEN il.reason = 'restock'    THEN il.change_quantity ELSE 0 END), 0) AS restocked_qty,
  COALESCE(SUM(CASE WHEN il.reason = 'adjustment' THEN il.change_quantity ELSE 0 END), 0) AS adjustment_qty,
  COALESCE(SUM(il.change_quantity), 0) AS logged_total,
  p.stock_quantity - COALESCE(SUM(il.change_quantity), 0) AS variance
FROM products AS p
LEFT JOIN inventory_logs AS il
  ON il.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.stock_quantity
ORDER BY p.product_id;

-- ------------------------------------------------------------
-- 7. Daily sales
-- ------------------------------------------------------------
SELECT
  o.order_date,
  COUNT(DISTINCT o.order_id) AS order_count,
  SUM(oi.quantity) AS units_sold,
  ROUND(SUM(oi.line_total), 2) AS net_revenue
FROM orders AS o
JOIN order_items AS oi
  ON oi.order_id = o.order_id
GROUP BY o.order_date
ORDER BY o.order_date;

-- ------------------------------------------------------------
-- 8. Monthly sales with month-over-month growth
-- ------------------------------------------------------------
WITH monthly AS (
  SELECT
    DATE_FORMAT(o.order_date, '%Y-%m') AS sales_month,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(oi.quantity) AS units_sold,
    ROUND(SUM(oi.line_total), 2) AS net_revenue
  FROM orders AS o
  JOIN order_items AS oi
    ON oi.order_id = o.order_id
  GROUP BY DATE_FORMAT(o.order_date, '%Y-%m')
)
SELECT
  sales_month,
  order_count,
  units_sold,
  net_revenue,
  LAG(net_revenue) OVER (ORDER BY sales_month) AS previous_month_revenue,
  ROUND(
    (net_revenue - LAG(net_revenue) OVER (ORDER BY sales_month))
    / NULLIF(LAG(net_revenue) OVER (ORDER BY sales_month), 0) * 100,
    2
  ) AS mom_growth_pct
FROM monthly
ORDER BY sales_month;

-- ------------------------------------------------------------
-- 9. Product rank within category
-- ------------------------------------------------------------
WITH product_sales AS (
  SELECT
    p.product_id,
    p.product_name,
    p.category,
    ROUND(SUM(oi.line_total), 2) AS net_revenue
  FROM order_items AS oi
  JOIN products AS p
    ON p.product_id = oi.product_id
  GROUP BY p.product_id, p.product_name, p.category
)
SELECT
  category,
  product_name,
  net_revenue,
  DENSE_RANK() OVER (
    PARTITION BY category
    ORDER BY net_revenue DESC
  ) AS rank_in_category
FROM product_sales
ORDER BY category, rank_in_category, product_name;

-- ------------------------------------------------------------
-- 10. Customer share of total spend
-- ------------------------------------------------------------
SELECT
  customer_id,
  full_name,
  total_spend,
  tier,
  DENSE_RANK() OVER (ORDER BY total_spend DESC) AS spend_rank,
  ROUND(
    total_spend / NULLIF(SUM(total_spend) OVER (), 0) * 100,
    2
  ) AS pct_of_total_spend
FROM v_customer_spend
ORDER BY spend_rank, customer_id;
