-- ============================================================
-- tests/sql/00_test_helpers.sql
-- Assertion helpers for the MySQL test suite.
--
-- These are created once. Test files only run DML and CALLs,
-- so their changes can be rolled back.
-- ============================================================

USE inventory_order_mgt;

DROP PROCEDURE IF EXISTS assert_true;

DELIMITER //
CREATE PROCEDURE assert_true(
  IN p_condition BOOLEAN,
  IN p_label VARCHAR(200)
)
BEGIN
  IF p_condition IS NULL OR p_condition = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = p_label;
  END IF;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS assert_raises;

DELIMITER //
CREATE PROCEDURE assert_raises(
  IN p_sql TEXT,
  IN p_expected_state CHAR(5),
  IN p_label VARCHAR(200)
)
BEGIN
  DECLARE v_state CHAR(5) DEFAULT '00000';
  DECLARE v_message TEXT;

  -- The handler is scoped to this inner block so the SIGNALs
  -- used to report a failed assertion are not swallowed.
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1
        v_state = RETURNED_SQLSTATE,
        v_message = MESSAGE_TEXT;
    END;

    SET @test_sql = p_sql;
    PREPARE test_stmt FROM @test_sql;
    EXECUTE test_stmt;
    DEALLOCATE PREPARE test_stmt;
  END;

  IF v_state = '00000' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Expected an error but the statement succeeded';
  ELSEIF v_state <> p_expected_state THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Statement failed with an unexpected SQLSTATE';
  END IF;
END //
DELIMITER ;

SELECT 'Test helpers created.' AS message;
