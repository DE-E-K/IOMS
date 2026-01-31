USE IOMS;

-- KPI AND ANALYTICS QUERIES
-- ============================================

-- 1. REAL-TIME DASHBOARD METRICS
DELIMITER $$

CREATE PROCEDURE GetDashboardMetrics(
    IN p_date_range ENUM('TODAY', 'WEEK', 'MONTH', 'QUARTER', 'YEAR')
)
BEGIN
    DECLARE v_start_date DATE;
    DECLARE v_end_date DATE DEFAULT CURDATE();
    
    -- Calculate date range
    SET v_start_date = CASE p_date_range
        WHEN 'TODAY' THEN CURDATE()
        WHEN 'WEEK' THEN DATE_SUB(CURDATE(), INTERVAL 7 DAY)
        WHEN 'MONTH' THEN DATE_SUB(CURDATE(), INTERVAL 30 DAY)
        WHEN 'QUARTER' THEN DATE_SUB(CURDATE(), INTERVAL 90 DAY)
        WHEN 'YEAR' THEN DATE_SUB(CURDATE(), INTERVAL 365 DAY)
    END;
    
    -- Return comprehensive dashboard metrics
    SELECT 
        -- Sales Metrics
        (SELECT COUNT(*) FROM orders 
         WHERE order_date BETWEEN v_start_date AND v_end_date 
         AND order_status NOT IN ('Cancelled', 'Returned')) as total_orders,
        
        (SELECT SUM(total_amount) FROM orders 
         WHERE order_date BETWEEN v_start_date AND v_end_date 
         AND order_status IN ('Delivered', 'Shipped')) as total_revenue,
        
        (SELECT AVG(total_amount) FROM orders 
         WHERE order_date BETWEEN v_start_date AND v_end_date 
         AND order_status NOT IN ('Cancelled', 'Returned')) as avg_order_value,
        
        -- Customer Metrics
        (SELECT COUNT(DISTINCT customer_id) FROM orders 
         WHERE order_date BETWEEN v_start_date AND v_end_date) as new_customers,
        
        (SELECT COUNT(*) FROM customer 
         WHERE customer_since BETWEEN v_start_date AND v_end_date) as total_new_customers,
        
        -- Inventory Metrics
        (SELECT COUNT(*) FROM inventory 
         WHERE quantity_available <= reorder_point) as low_stock_items,
        
        (SELECT COUNT(*) FROM inventory 
         WHERE quantity_available = 0) as out_of_stock_items,
        
        -- Fulfillment Metrics
        (SELECT COUNT(*) FROM orders 
         WHERE order_status = 'Pending' 
         AND order_date BETWEEN v_start_date AND v_end_date) as pending_orders,
        
        (SELECT COUNT(*) FROM orders 
         WHERE order_status = 'Processing' 
         AND order_date BETWEEN v_start_date AND v_end_date) as processing_orders,
        
        (SELECT AVG(DATEDIFF(actual_delivery_date, order_date)) 
         FROM orders 
         WHERE order_status = 'Delivered' 
         AND actual_delivery_date IS NOT NULL
         AND order_date BETWEEN v_start_date AND v_end_date) as avg_delivery_days,
        
        -- Return Metrics
        (SELECT COUNT(*) FROM returns 
         WHERE return_date BETWEEN v_start_date AND v_end_date) as total_returns,
        
        (SELECT SUM(refund_amount) FROM returns 
         WHERE return_status = 'Refunded' 
         AND return_date BETWEEN v_start_date AND v_end_date) as total_refunds;
END$$

-- 2. TOP PERFORMERS ANALYSIS
CREATE PROCEDURE GetTopPerformers(
    IN p_limit INT,
    IN p_period ENUM('DAY', 'WEEK', 'MONTH', 'YEAR')
)
BEGIN
    DECLARE v_start_date DATE;
    
    SET v_start_date = CASE p_period
        WHEN 'DAY' THEN CURDATE()
        WHEN 'WEEK' THEN DATE_SUB(CURDATE(), INTERVAL 7 DAY)
        WHEN 'MONTH' THEN DATE_SUB(CURDATE(), INTERVAL 30 DAY)
        WHEN 'YEAR' THEN DATE_SUB(CURDATE(), INTERVAL 365 DAY)
    END;
    
    -- Top Customers
    SELECT 'TOP_CUSTOMERS' as category, c.customer_id, c.full_name, 
           SUM(o.total_amount) as value, COUNT(o.order_id) as orders
    FROM customer c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_date >= v_start_date 
    AND o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY c.customer_id, c.full_name
    ORDER BY value DESC
    LIMIT p_limit;
    
    -- Top Products
    SELECT 'TOP_PRODUCTS' as category, p.product_id, p.product_name,
           SUM(oi.quantity) as quantity_sold,
           SUM(oi.quantity * oi.unit_price_at_purchase) as revenue
    FROM product p
    JOIN order_item oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_date >= v_start_date 
    AND o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY p.product_id, p.product_name
    ORDER BY revenue DESC
    LIMIT p_limit;
    
    -- Top Categories
    SELECT 'TOP_CATEGORIES' as category, pc.category_name,
           SUM(oi.quantity) as quantity_sold,
           SUM(oi.quantity * oi.unit_price_at_purchase) as revenue,
           COUNT(DISTINCT o.customer_id) as unique_customers
    FROM product_category pc
    JOIN product p ON pc.category_id = p.category_id
    JOIN order_item oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_date >= v_start_date 
    AND o.order_status NOT IN ('Cancelled', 'Returned')
    GROUP BY pc.category_id, pc.category_name
    ORDER BY revenue DESC
    LIMIT p_limit;
END$$

-- 3. SALES TREND ANALYSIS
CREATE PROCEDURE AnalyzeSalesTrend(
    IN p_start_date DATE,
    IN p_end_date DATE,
    IN p_granularity ENUM('DAILY', 'WEEKLY', 'MONTHLY', 'QUARTERLY')
)
BEGIN
    SET @sql = CONCAT(
        'SELECT ',
        CASE p_granularity
            WHEN 'DAILY' THEN 'DATE(order_date) as period'
            WHEN 'WEEKLY' THEN 'DATE_FORMAT(order_date, "%Y-%u") as period'
            WHEN 'MONTHLY' THEN 'DATE_FORMAT(order_date, "%Y-%m") as period'
            WHEN 'QUARTERLY' THEN 'CONCAT(YEAR(order_date), "-Q", QUARTER(order_date)) as period'
        END,
        ', COUNT(*) as order_count, ',
        'COUNT(DISTINCT customer_id) as unique_customers, ',
        'SUM(total_amount) as total_revenue, ',
        'AVG(total_amount) as avg_order_value, ',
        'SUM(CASE WHEN order_status = "Delivered" THEN total_amount ELSE 0 END) as delivered_revenue, ',
        'SUM(CASE WHEN order_status = "Cancelled" THEN 1 ELSE 0 END) as cancelled_orders ',
        'FROM orders ',
        'WHERE order_date BETWEEN ? AND ? ',
        'AND order_status NOT IN ("Returned") ',
        'GROUP BY period ',
        'ORDER BY period'
    );
    
    PREPARE stmt FROM @sql;
    SET @start_date = p_start_date;
    SET @end_date = p_end_date;
    EXECUTE stmt USING @start_date, @end_date;
    DEALLOCATE PREPARE stmt;
END$$
DELIMITER ;

-- 4. GENERATE SALES REPORT
CREATE PROCEDURE GenerateSalesReport(
    IN p_start_date DATE,
    IN p_end_date DATE,
    IN p_category_id INT,
    IN p_customer_id INT
)
BEGIN
    -- Sales Summary
    SELECT 
        'SUMMARY' as report_section,
        COUNT(DISTINCT o.order_id) as total_orders,
        COUNT(DISTINCT o.customer_id) as unique_customers,
        SUM(o.total_amount) as total_revenue,
        AVG(o.total_amount) as avg_order_value,
        SUM(o.tax_amount) as total_tax,
        SUM(o.shipping_amount) as total_shipping,
        SUM(o.discount_amount) as total_discount,
        SUM(oi.quantity) as total_items_sold,
        SUM(CASE WHEN o.order_status = 'Delivered' THEN o.total_amount ELSE 0 END) as delivered_revenue,
        SUM(CASE WHEN o.order_status = 'Cancelled' THEN o.total_amount ELSE 0 END) as cancelled_revenue,
        SUM(CASE WHEN o.order_status = 'Returned' THEN o.total_amount ELSE 0 END) as returned_revenue
    FROM orders o
    LEFT JOIN order_item oi ON o.order_id = oi.order_id
    WHERE o.order_date BETWEEN p_start_date AND p_end_date
    AND (p_category_id IS NULL OR EXISTS (
        SELECT 1 FROM order_item oi2 
        JOIN product p ON oi2.product_id = p.product_id
        WHERE oi2.order_id = o.order_id AND p.category_id = p_category_id
    ))
    AND (p_customer_id IS NULL OR o.customer_id = p_customer_id);
    
    -- Sales by Category
    SELECT 
        'BY_CATEGORY' as report_section,
        pc.category_name,
        COUNT(DISTINCT o.order_id) as order_count,
        SUM(oi.quantity) as quantity_sold,
        SUM(oi.quantity * oi.unit_price_at_purchase) as revenue,
        AVG(oi.unit_price_at_purchase) as avg_unit_price,
        COUNT(DISTINCT o.customer_id) as unique_customers
    FROM product_category pc
    JOIN product p ON pc.category_id = p.category_id
    JOIN order_item oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_date BETWEEN p_start_date AND p_end_date
    AND (p_category_id IS NULL OR p.category_id = p_category_id)
    AND (p_customer_id IS NULL OR o.customer_id = p_customer_id)
    GROUP BY pc.category_id, pc.category_name
    ORDER BY revenue DESC;
    
    -- Top Products
    SELECT 
        'TOP_PRODUCTS' as report_section,
        p.product_name,
        p.sku,
        pc.category_name,
        SUM(oi.quantity) as quantity_sold,
        SUM(oi.quantity * oi.unit_price_at_purchase) as revenue,
        AVG(oi.unit_price_at_purchase) as avg_selling_price,
        COUNT(DISTINCT o.order_id) as times_ordered,
        COUNT(DISTINCT o.customer_id) as unique_customers
    FROM product p
    JOIN product_category pc ON p.category_id = pc.category_id
    JOIN order_item oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_date BETWEEN p_start_date AND p_end_date
    AND o.order_status NOT IN ('Cancelled', 'Returned')
    AND (p_category_id IS NULL OR p.category_id = p_category_id)
    AND (p_customer_id IS NULL OR o.customer_id = p_customer_id)
    GROUP BY p.product_id, p.product_name, p.sku, pc.category_name
    ORDER BY revenue DESC
    LIMIT 20;
    
    -- Sales Trend (Daily)
    SELECT 
        'DAILY_TREND' as report_section,
        DATE(o.order_date) as sales_date,
        COUNT(DISTINCT o.order_id) as order_count,
        SUM(o.total_amount) as daily_revenue,
        SUM(oi.quantity) as items_sold,
        COUNT(DISTINCT o.customer_id) as daily_customers
    FROM orders o
    LEFT JOIN order_item oi ON o.order_id = oi.order_id
    WHERE o.order_date BETWEEN p_start_date AND p_end_date
    AND (p_customer_id IS NULL OR o.customer_id = p_customer_id)
    GROUP BY DATE(o.order_date)
    ORDER BY sales_date;
    
    -- Customer Analysis
    SELECT 
        'CUSTOMER_ANALYSIS' as report_section,
        c.customer_id,
        c.full_name,
        c.email,
        COUNT(DISTINCT o.order_id) as order_count,
        SUM(o.total_amount) as total_spent,
        AVG(o.total_amount) as avg_order_value,
        MIN(o.order_date) as first_order_date,
        MAX(o.order_date) as last_order_date,
        DATEDIFF(p_end_date, MAX(o.order_date)) as days_since_last_order
    FROM customer c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_date BETWEEN p_start_date AND p_end_date
    AND (p_customer_id IS NULL OR c.customer_id = p_customer_id)
    GROUP BY c.customer_id, c.full_name, c.email
    ORDER BY total_spent DESC;
    
END$$