-- ============================================
-- KPI & ANALYTICAL QUERIES
-- ============================================

-- 1. VIEW: Customer Sales Summary
-- Pre-calculates total spending and order count for easier analysis
DROP VIEW IF EXISTS CustomerSalesSummary;
CREATE VIEW CustomerSalesSummary AS
SELECT 
    c.customer_id,
    c.full_name,
    c.email,
    COALESCE(SUM(o.total_amount), 0) AS total_spent,
    COUNT(DISTINCT o.order_id) AS total_orders,
    AVG(o.total_amount) AS avg_order_value,
    MAX(o.order_date) AS last_order_date
FROM customer c
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.order_status NOT IN ('Cancelled', 'Returned')
GROUP BY c.customer_id, c.full_name, c.email;

-- 2. KPI: Total Revenue
-- Calculate revenue from completed orders
SELECT 
    'Total Revenue' AS KPI,
    SUM(total_amount) AS Value
FROM orders
WHERE order_status IN ('Shipped', 'Delivered');

-- 3. KPI: Top 10 Customers
-- Find top customers by spending
SELECT 
    customer_id, 
    full_name, 
    total_spent 
FROM CustomerSalesSummary
ORDER BY total_spent DESC 
LIMIT 10;

-- 4. KPI: Best-Selling Products
-- Top 5 products by quantity sold
SELECT 
    p.product_id, 
    p.product_name, 
    SUM(oi.quantity) AS total_sold
FROM order_item oi
JOIN product p ON oi.product_id = p.product_id
JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned')
GROUP BY p.product_id, p.product_name
ORDER BY total_sold DESC 
LIMIT 5;

-- 5. KPI: Monthly Sales Trend
-- Revenue grouped by month
SELECT 
    DATE_FORMAT(order_date, '%Y-%m') AS sales_month,
    COUNT(order_id) AS total_orders,
    SUM(total_amount) AS revenue
FROM orders
WHERE order_status NOT IN ('Cancelled', 'Returned')
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY sales_month;

-- 6. ANALYTICS: Sales Rank by Category (Window Function)
-- Rank products within their category based on revenue
SELECT 
    pc.category_name,
    p.product_name,
    SUM(oi.quantity * oi.unit_price) AS product_revenue,
    RANK() OVER (
        PARTITION BY pc.category_name 
        ORDER BY SUM(oi.quantity * oi.unit_price) DESC
    ) AS rank_in_category
FROM order_item oi
JOIN product p ON oi.product_id = p.product_id
JOIN product_category pc ON p.category_id = pc.category_id
JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_status NOT IN ('Cancelled', 'Returned')
GROUP BY pc.category_name, p.product_name;

-- 7. ANALYTICS: Customer Order Frequency (Window Function)
-- Compare current order date with previous order date
SELECT 
    c.full_name,
    o.order_id,
    o.order_date,
    LAG(o.order_date) OVER (
        PARTITION BY c.customer_id 
        ORDER BY o.order_date
    ) AS previous_order_date,
    DATEDIFF(o.order_date, LAG(o.order_date) OVER (
        PARTITION BY c.customer_id 
        ORDER BY o.order_date
    )) AS days_since_last_order
FROM orders o
JOIN customer c ON o.customer_id = c.customer_id
ORDER BY c.customer_id, o.order_date;
