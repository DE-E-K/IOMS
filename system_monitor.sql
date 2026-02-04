-- Current system status
-- ============================================
USE IOMS;
SELECT 
    'SYSTEM_STATUS' as report,
    (SELECT COUNT(*) FROM orders WHERE order_status = 'Pending') as pending_orders,
    (SELECT COUNT(*) FROM low_stock_alerts WHERE resolved = FALSE AND alert_level = 'CRITICAL') as critical_alerts,
    (SELECT COUNT(*) FROM system_error_log WHERE resolved = FALSE AND severity = 'HIGH') as high_errors,
    (SELECT MAX(order_date) FROM orders) as last_order_time,
    (SELECT COUNT(*) FROM active_connections_log) as active_connections_logs;

-- Recent errors
SELECT 
    error_time,
    error_code,
    error_message,
    stored_procedure,
    severity
FROM system_error_log
WHERE resolved = FALSE
ORDER BY error_time DESC
LIMIT 10;

-- Performance issues
SELECT 
    timestamp,
    query_type,
    execution_time_ms,
    rows_affected,
    query_text
FROM query_performance_log
WHERE execution_time_ms > 1000
ORDER BY execution_time_ms DESC
LIMIT 10;


-- Verify all procedures are created
SELECT 
    'PROCEDURES_CREATED' as verification,
    COUNT(*) as count
FROM information_schema.routines
WHERE routine_schema = 'IOM'
AND routine_type = 'PROCEDURE';

-- Verify all views are created
SELECT 
    'VIEWS_CREATED' as verification,
    COUNT(*) as count
FROM information_schema.views
WHERE table_schema = 'IOM';

-- Check event scheduler status
SHOW EVENTS FROM IOM;

-- Show table statistics
SELECT 
    table_name,
    table_rows,
    ROUND((data_length + index_length) / 1024 / 1024, 2) as size_mb,
    CREATE_TIME,
    UPDATE_TIME
FROM information_schema.tables
WHERE table_schema = 'IOMS'
ORDER BY table_rows DESC;

-- Final success message
SELECT 'Database setup and procedures completed successfully' as final_status;