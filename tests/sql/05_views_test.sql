-- ============================================================
-- tests/sql/05_views_test.sql
-- Expected rows and values for the reporting views.
-- ============================================================

USE inventory_order_mgt;

START TRANSACTION;

CALL assert_true(
  (SELECT COUNT(*) FROM v_order_summary) = 5,
  'order summary has five seed orders'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_order_summary
    WHERE order_id = 1
      AND customer_name = 'Ama Mensah'
      AND total_amount = 50.50
      AND item_count = 4) = 1,
  'order 1 summary is correct'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_order_summary
    WHERE order_id = 4
      AND total_amount = 126.50
      AND item_count = 12) = 1,
  'order 4 summary and discount total are correct'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_low_stock) = 3,
  'low-stock view has three products'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_low_stock WHERE product_id IN (2, 4, 5)) = 3,
  'low-stock view contains mouse, monitor and stand'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_customer_spend
    WHERE customer_id = 1
      AND total_spend = 548.50
      AND tier = 'Gold') = 1,
  'Ama is Gold'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_customer_spend
    WHERE customer_id = 2
      AND total_spend = 355.99
      AND tier = 'Silver') = 1,
  'Kofi is Silver'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_customer_spend
    WHERE customer_id = 3
      AND total_spend = 126.50
      AND tier = 'Bronze') = 1,
  'Esi is Bronze'
);

CALL assert_true(
  (SELECT COUNT(*) FROM v_customer_spend
    WHERE customer_id = 4
      AND total_spend = 0.00
      AND tier = 'Bronze') = 1,
  'Yaw is Bronze with zero spend'
);

CALL assert_true(
  (SELECT ROUND(SUM(total_spend), 2) FROM v_customer_spend) = 1030.99,
  'customer spend totals 1030.99'
);

SELECT '05_views_test passed' AS result;

ROLLBACK;
