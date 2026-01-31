/*
VIEWS
INVENTORY ORDERS MANAGEMENT SYSTEM VIEW DEFINITIONS
*/
-- ============================================

-- View 1: Customer Sales Summary
USE IOMS;
CREATE VIEW v_customer_sales_summary AS
SELECT 
    c.customer_id,
    c.full_name,
    c.email,
    c.phone,
    c.customer_since,
    c.total_lifetime_value,
    cl.loyalty_tier,
    cl.loyalty_points,
    COUNT(DISTINCT o.order_id) as total_orders,
    SUM(oi.quantity) as total_items_purchased,
    MAX(o.order_date) as last_order_date,
    DATEDIFF(CURDATE(), MAX(o.order_date)) as days_since_last_order
FROM customer c
LEFT JOIN customer_loyalty cl ON c.customer_id = cl.customer_id
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.order_status NOT IN ('Cancelled', 'Returned')
LEFT JOIN order_item oi ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.full_name, c.email, c.phone, c.customer_since, c.total_lifetime_value, cl.loyalty_tier, cl.loyalty_points;

-- View 2: Product Performance Summary
CREATE VIEW v_product_performance AS
SELECT 
    p.product_id,
    p.product_name,
    p.sku,
    pc.category_name,
    p.brand,
    p.price,
    i.quantity_on_hand,
    i.quantity_available,
    i.reorder_point,
    COALESCE(SUM(oi.quantity), 0) as total_sold,
    COALESCE(SUM(oi.quantity * oi.unit_price), 0) as total_revenue,
    COALESCE(AVG(oi.unit_price), 0) as avg_selling_price,
    COUNT(DISTINCT o.customer_id) as unique_customers,
    p.rating,
    p.review_count
FROM product p
JOIN product_category pc ON p.category_id = pc.category_id
LEFT JOIN inventory i ON p.product_id = i.product_id
LEFT JOIN order_item oi ON p.product_id = oi.product_id
LEFT JOIN orders o ON oi.order_id = o.order_id AND o.order_status NOT IN ('Cancelled', 'Returned')
GROUP BY p.product_id, p.product_name, p.sku, pc.category_name, p.brand, p.price, i.quantity_on_hand, i.quantity_available, i.reorder_point, p.rating, p.review_count;

-- View 3: Daily Sales Dashboard
CREATE VIEW v_daily_sales_dashboard AS
SELECT 
    DATE(o.order_date) as sales_date,
    COUNT(DISTINCT o.order_id) as total_orders,
    COUNT(DISTINCT o.customer_id) as unique_customers,
    SUM(o.total_amount) as daily_revenue,
    AVG(o.total_amount) as avg_order_value,
    SUM(oi.quantity) as total_items_sold,
    SUM(CASE WHEN o.order_status = 'Delivered' THEN o.total_amount ELSE 0 END) as delivered_revenue,
    SUM(CASE WHEN o.order_status IN ('Pending', 'Processing') THEN 1 ELSE 0 END) as pending_orders
FROM orders o
LEFT JOIN order_item oi ON o.order_id = oi.order_id
WHERE o.order_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY DATE(o.order_date)
ORDER BY sales_date DESC;

-- View 4: Inventory Status
CREATE VIEW v_inventory_status AS
SELECT 
    p.product_id,
    p.product_name,
    p.sku,
    pc.category_name,
    i.quantity_on_hand,
    i.quantity_reserved,
    i.quantity_available,
    i.reorder_point,
    i.reorder_quantity,
    CASE 
        WHEN i.quantity_available <= 0 THEN 'Out of Stock'
        WHEN i.quantity_available <= i.reorder_point THEN 'Low Stock'
        WHEN i.quantity_available <= i.reorder_point * 2 THEN 'Medium Stock'
        ELSE 'In Stock'
    END as stock_status,
    DATEDIFF(CURDATE(), i.last_restock_date) as days_since_restock,
    COALESCE(lsa.alert_level, 'NONE') as active_alert_level
FROM product p
JOIN product_category pc ON p.category_id = pc.category_id
JOIN inventory i ON p.product_id = i.product_id
LEFT JOIN (
    SELECT product_id, MAX(alert_level) as alert_level
    FROM low_stock_alerts 
    WHERE resolved = FALSE
    GROUP BY product_id
) lsa ON p.product_id = lsa.product_id
WHERE p.is_active = TRUE;

-- View 5: Order Fulfillment Status
CREATE VIEW v_order_fulfillment AS
SELECT 
    o.order_id,
    o.order_number,
    o.order_date,
    c.full_name,
    o.order_status,
    o.payment_status,
    o.total_amount,
    s.shipping_method,
    s.tracking_number,
    s.estimated_delivery_date,
    s.actual_delivery_date,
    COUNT(DISTINCT oi.product_id) as unique_items,
    SUM(oi.quantity) as total_items,
    DATEDIFF(CURDATE(), o.order_date) as days_since_order,
    CASE 
        WHEN o.order_status = 'Delivered' THEN 'Completed'
        WHEN o.order_status = 'Shipped' THEN 'In Transit'
        WHEN o.order_status = 'Processing' THEN 'Processing'
        WHEN o.order_status = 'Pending' THEN 'Pending'
        ELSE o.order_status
    END as fulfillment_stage
FROM orders o
JOIN customer c ON o.customer_id = c.customer_id
LEFT JOIN shipping_info s ON o.order_id = s.order_id
LEFT JOIN order_item oi ON o.order_id = oi.order_id
GROUP BY o.order_id, o.order_number, o.order_date, c.full_name, o.order_status, o.payment_status, o.total_amount, s.shipping_method, s.tracking_number, s.estimated_delivery_date, s.actual_delivery_date;
