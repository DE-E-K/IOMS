-- EVENT SCHEDULERS
-- ============================================
USE IOMS;
DELIMITER $$

-- Event 1: Daily summary update
CREATE EVENT e_daily_summary_update
ON SCHEDULE EVERY 1 DAY
STARTS CONCAT(CURDATE() + INTERVAL 1 DAY, ' 02:00:00')
DO
BEGIN
    -- Update customer summary
    INSERT INTO customer_summary_daily (
        summary_date,
        customer_id,
        total_spent,
        total_orders,
        avg_order_value,
        days_since_last_order,
        last_order_date,
        last_order_amount
    )
    SELECT 
        CURDATE() - INTERVAL 1 DAY,
        c.customer_id,
        c.total_lifetime_value,
        COUNT(DISTINCT o.order_id),
        AVG(o.total_amount),
        DATEDIFF(CURDATE(), MAX(o.order_date)),
        MAX(o.order_date),
        MAX(CASE WHEN o.order_date = MAX(o.order_date) THEN o.total_amount ELSE NULL END)
    FROM customer c
    LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY c.customer_id
    ON DUPLICATE KEY UPDATE
        total_spent = VALUES(total_spent),
        total_orders = VALUES(total_orders),
        avg_order_value = VALUES(avg_order_value),
        days_since_last_order = VALUES(days_since_last_order),
        last_order_date = VALUES(last_order_date),
        last_order_amount = VALUES(last_order_amount);
    
    -- Update product sales summary
    INSERT INTO product_sales_summary (
        summary_date,
        product_id,
        quantity_sold,
        total_revenue,
        avg_selling_price,
        unique_customers
    )
    SELECT 
        CURDATE() - INTERVAL 1 DAY,
        oi.product_id,
        SUM(oi.quantity),
        SUM(oi.quantity * oi.unit_price_at_purchase),
        AVG(oi.unit_price_at_purchase),
        COUNT(DISTINCT o.customer_id)
    FROM order_item oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE DATE(o.order_date) = CURDATE() - INTERVAL 1 DAY
        AND o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY oi.product_id
    ON DUPLICATE KEY UPDATE
        quantity_sold = VALUES(quantity_sold),
        total_revenue = VALUES(total_revenue),
        avg_selling_price = VALUES(avg_selling_price),
        unique_customers = VALUES(unique_customers);
END$$

-- Event 2: Clean old logs
CREATE EVENT e_clean_old_logs
ON SCHEDULE EVERY 2 WEEK
STARTS CONCAT(CURDATE() + INTERVAL 14 DAY, ' 03:00:00')
DO
BEGIN
    -- Archive and delete old logs (keep 90 days)
    DELETE FROM system_error_log 
    WHERE error_time < DATE_SUB(CURDATE(), INTERVAL 90 DAY) 
    AND resolved = TRUE;
    
    DELETE FROM query_performance_log 
    WHERE timestamp < DATE_SUB(CURDATE(), INTERVAL 90 DAY);
    
    DELETE FROM active_connections_log 
    WHERE logged_at < DATE_SUB(CURDATE(), INTERVAL 30 DAY);
    
    -- Archive old business rule violations
    UPDATE business_rule_violations 
    SET resolved = TRUE,
        resolved_at = CURRENT_TIMESTAMP,
        resolution_notes = CONCAT('Auto-resolved by cleanup job after 180 days')
    WHERE detected_at < DATE_SUB(CURDATE(), INTERVAL 180 DAY)
    AND resolved = FALSE;
END$$

-- Event 3: Check for stale low stock alerts
CREATE EVENT e_check_stale_alerts
ON SCHEDULE EVERY 1 DAY
STARTS CONCAT(CURDATE() + INTERVAL 1 DAY, ' 04:00:00')
DO
BEGIN
    -- Resolve alerts that are no longer relevant
    UPDATE low_stock_alerts lsa
    JOIN inventory i ON lsa.product_id = i.product_id
    SET lsa.resolved = TRUE,
        lsa.resolved_at = CURRENT_TIMESTAMP
    WHERE lsa.resolved = FALSE
    AND i.quantity_on_hand > lsa.reorder_point
    AND lsa.alert_date < DATE_SUB(CURDATE(), INTERVAL 7 DAY);
END$$

DELIMITER ;


-- Enable event scheduler
SET GLOBAL event_scheduler = ON;

-- Set timezone
SET time_zone = '+02:00'; -- Central Africa Time
