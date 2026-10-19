-- ============================================================
-- 00_reset.sql
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
