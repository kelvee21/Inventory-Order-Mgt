-- ============================================================
-- sql/09_quality/09_data_quality_checks.sql
-- Read-only integrity checks. Every row should say PASS.
--
-- These are deliberately set-based: they can be rerun after a
-- demo order or a restock without changing the data.
-- ============================================================

USE inventory_order_mgt;

SELECT 'stock equals sum of inventory logs' AS check_name,
       COUNT(*) AS issues,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
  SELECT p.product_id
  FROM products AS p
  LEFT JOIN inventory_logs AS il
    ON il.product_id = p.product_id
  GROUP BY p.product_id, p.stock_quantity
  HAVING p.stock_quantity <> COALESCE(SUM(il.change_quantity), 0)
) AS mismatches

UNION ALL

SELECT 'order total equals sum of line totals',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM orders AS o
LEFT JOIN (
  SELECT order_id, SUM(line_total) AS line_sum
  FROM order_items
  GROUP BY order_id
) AS totals
  ON totals.order_id = o.order_id
WHERE o.total_amount <> COALESCE(totals.line_sum, 0)

UNION ALL

SELECT 'every order has at least one item',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM orders AS o
WHERE NOT EXISTS (
  SELECT 1 FROM order_items AS oi WHERE oi.order_id = o.order_id
)

UNION ALL

SELECT 'every order item belongs to an order',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM order_items AS oi
LEFT JOIN orders AS o
  ON o.order_id = oi.order_id
WHERE o.order_id IS NULL

UNION ALL

SELECT 'every inventory log belongs to a product',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM inventory_logs AS il
LEFT JOIN products AS p
  ON p.product_id = il.product_id
WHERE p.product_id IS NULL

UNION ALL

SELECT 'order lines have valid quantity and price',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM order_items
WHERE quantity <= 0
   OR unit_price < 0
   OR line_total < 0
   OR discount_rate < 0
   OR discount_rate > 1

UNION ALL

SELECT 'line totals match quantity, price and discount',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM order_items
WHERE line_total <> ROUND(
  quantity * unit_price * (1 - discount_rate),
  2
)

UNION ALL

SELECT 'discount rates follow the bulk rule',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM order_items
WHERE discount_rate <> bulk_discount_rate(quantity)

UNION ALL

SELECT 'sale logs match order-line quantities',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM order_items AS oi
LEFT JOIN inventory_logs AS il
  ON il.order_id = oi.order_id
 AND il.product_id = oi.product_id
 AND il.reason = 'order'
WHERE il.log_id IS NULL
   OR il.change_quantity <> -oi.quantity

UNION ALL

SELECT 'stock and reorder levels are non-negative',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM products
WHERE stock_quantity < 0
   OR reorder_level < 0
   OR price < 0

UNION ALL

SELECT 'inventory log changes and reasons are valid',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM inventory_logs
WHERE change_quantity = 0
   OR reason NOT IN ('opening', 'order', 'restock', 'adjustment')
   OR (reason = 'order' AND order_id IS NULL)
   OR (reason IN ('opening', 'restock') AND order_id IS NOT NULL)

UNION ALL

SELECT 'customer emails are unique',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
  SELECT email
  FROM customers
  GROUP BY email
  HAVING COUNT(*) > 1
) AS duplicate_emails

UNION ALL

SELECT 'customer emails pass the format check',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM customers
WHERE email NOT LIKE '%_@_%._%'

UNION ALL

SELECT 'order lines are unique per order and product',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
  SELECT order_id, product_id
  FROM order_items
  GROUP BY order_id, product_id
  HAVING COUNT(*) > 1
) AS duplicate_lines

UNION ALL

SELECT 'low-stock view matches the product rule',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
  SELECT p.product_id
  FROM products AS p
  LEFT JOIN v_low_stock AS v
    ON v.product_id = p.product_id
  WHERE (p.stock_quantity < p.reorder_level AND v.product_id IS NULL)
     OR (p.stock_quantity >= p.reorder_level AND v.product_id IS NOT NULL)
) AS low_stock_mismatches

UNION ALL

SELECT 'customer tiers match total spend',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM v_customer_spend
WHERE tier <> customer_tier(total_spend);
