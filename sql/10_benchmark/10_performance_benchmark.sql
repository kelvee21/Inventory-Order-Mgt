-- ============================================================
-- sql/10_benchmark/10_performance_benchmark.sql
-- Compare the customer-order query before and after adding a
-- composite index on a 200,000-row synthetic table.
--
-- This uses a temporary table, so it does not touch the lab data.
-- ============================================================

USE inventory_order_mgt;

DROP TEMPORARY TABLE IF EXISTS big_orders;

CREATE TEMPORARY TABLE big_orders (
  order_id    INT NOT NULL PRIMARY KEY,
  customer_id INT NOT NULL,
  order_date  DATE NOT NULL
) ENGINE=InnoDB;

SET SESSION cte_max_recursion_depth = 200000;

INSERT INTO big_orders (order_id, customer_id, order_date)
SELECT
  n,
  1 + (n % 5000),
  DATE_ADD('2026-01-01', INTERVAL (n % 270) DAY)
FROM (
  WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 200000
  )
  SELECT n FROM seq
) AS s;

ANALYZE TABLE big_orders;

SELECT 'Before index' AS phase;

EXPLAIN ANALYZE
SELECT order_id, order_date
FROM big_orders
WHERE customer_id = 42
ORDER BY order_date DESC;

CREATE INDEX idx_big_orders_customer_date
  ON big_orders (customer_id, order_date);

ANALYZE TABLE big_orders;

SELECT 'After index' AS phase;

EXPLAIN ANALYZE
SELECT order_id, order_date
FROM big_orders
WHERE customer_id = 42
ORDER BY order_date DESC;

DROP TEMPORARY TABLE big_orders;
