-- Inventory and Order Management System (IOMS)
-- ENHANCED SCHEMA IMPLEMENTATION
-- Version: 2.0 (Supports Advanced Logic)

DROP DATABASE IF EXISTS IOMS;
CREATE DATABASE IF NOT EXISTS IOMS;
USE IOMS;

-- 1. CORE TABLES
-- =============================================

-- CUSTOMER & LOYALTY
CREATE TABLE customer (
  customer_id INT PRIMARY KEY AUTO_INCREMENT,
  full_name VARCHAR(100) NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE CHECK (email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'),
  phone VARCHAR(20),
  shipping_address VARCHAR(255),
  is_active BOOLEAN DEFAULT TRUE,
  -- Fields for automations
  total_lifetime_value DECIMAL(12,2) DEFAULT 0,
  last_purchase_date DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customer_loyalty (
    loyalty_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL UNIQUE,
    loyalty_tier ENUM('Bronze', 'Silver', 'Gold', 'Platinum') DEFAULT 'Bronze',
    loyalty_points INT DEFAULT 0,
    points_earned INT DEFAULT 0,
    total_spent DECIMAL(12,2) DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON DELETE CASCADE
);

-- PRODUCTS & CATEGORIES
CREATE TABLE product_category (
    category_id INT PRIMARY KEY AUTO_INCREMENT,
    category_name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE product (
  product_id INT PRIMARY KEY AUTO_INCREMENT,
  product_name VARCHAR(255) NOT NULL UNIQUE,
  category_id INT NOT NULL, -- Normalized from ENUM
  sku VARCHAR(50) UNIQUE,
  price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
  cost_price DECIMAL(10,2) CHECK (cost_price >= 0),
  is_active BOOLEAN DEFAULT TRUE,
  -- Analytics fields
  rating DECIMAL(3,2) DEFAULT 0,
  review_count INT DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (category_id) REFERENCES product_category(category_id)
);

-- INVENTORY MANAGEMENT
CREATE TABLE suppliers (
    supplier_id INT PRIMARY KEY AUTO_INCREMENT,
    supplier_name VARCHAR(100) NOT NULL,
    contact_email VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE inventory (
  inventory_id INT PRIMARY KEY AUTO_INCREMENT,
  product_id INT NOT NULL UNIQUE,
  quantity_on_hand INT NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
  quantity_reserved INT NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
  -- Virtual computed column for available stock
  quantity_available INT GENERATED ALWAYS AS (quantity_on_hand - quantity_reserved) VIRTUAL,
  reorder_point INT NOT NULL DEFAULT 10 CHECK (reorder_point >= 0),
  reorder_quantity INT NOT NULL DEFAULT 20 CHECK (reorder_quantity > 0),
  last_restock_date DATETIME,
  last_updated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (product_id) REFERENCES product(product_id) ON DELETE CASCADE
);

CREATE TABLE inventory_batch (
    batch_id INT PRIMARY KEY AUTO_INCREMENT,
    product_id INT NOT NULL,
    batch_number VARCHAR(50),
    supplier_id INT,
    quantity_received INT NOT NULL,
    quantity_remaining INT NOT NULL,
    unit_cost DECIMAL(10,2),
    received_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    expiration_date DATE,
    FOREIGN KEY (product_id) REFERENCES product(product_id),
    FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
);

-- PROMOTIONS
CREATE TABLE promotions (
    promotion_id INT PRIMARY KEY AUTO_INCREMENT,
    promotion_code VARCHAR(50) NOT NULL UNIQUE,
    promotion_name VARCHAR(100),
    promotion_type ENUM('Percentage', 'Fixed Amount', 'Free Shipping') NOT NULL,
    discount_value DECIMAL(10,2) NOT NULL,
    minimum_order_amount DECIMAL(10,2) DEFAULT 0,
    maximum_discount_amount DECIMAL(10,2),
    valid_from DATETIME NOT NULL,
    valid_to DATETIME NOT NULL,
    max_uses_total INT,
    times_used INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE
);

-- 2. TRANSACTION TABLES
-- =============================================

-- ORDERS
CREATE TABLE orders (
  order_id INT PRIMARY KEY AUTO_INCREMENT,
  order_number VARCHAR(50) UNIQUE, -- Generated ID
  customer_id INT NOT NULL,
  order_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  
  -- Financials
  subtotal DECIMAL(10,2) NOT NULL DEFAULT 0,
  tax_amount DECIMAL(10,2) DEFAULT 0,
  shipping_amount DECIMAL(10,2) DEFAULT 0,
  discount_amount DECIMAL(10,2) DEFAULT 0,
  total_amount DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  
  -- Status flow
  order_status ENUM('Pending','Processing','Shipped','Delivered','Cancelled', 'Returned') DEFAULT 'Pending',
  payment_status ENUM('Pending', 'Paid', 'Refunded', 'Failed') DEFAULT 'Pending',
  payment_method VARCHAR(50),
  shipping_method VARCHAR(50),
  
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  
  FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON DELETE RESTRICT
);

-- Generate Order Number Trigger (Simple version for MySQL 8)
DELIMITER ;;
CREATE TRIGGER before_order_insert 
BEFORE INSERT ON orders
FOR EACH ROW 
BEGIN
    IF NEW.order_number IS NULL THEN
        SET NEW.order_number = CONCAT('ORD-', DATE_FORMAT(NOW(), '%Y%m%d'), '-', UUID_SHORT());
    END IF;
END;;
DELIMITER ;

CREATE TABLE order_item (
  order_item_id INT PRIMARY KEY AUTO_INCREMENT,
  order_id INT NOT NULL,
  product_id INT NOT NULL,
  quantity INT NOT NULL CHECK (quantity > 0),
  unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
  
  FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES product(product_id) ON DELETE RESTRICT
);

-- SHIPPING INFO
CREATE TABLE shipping_info (
    shipping_id INT PRIMARY KEY AUTO_INCREMENT,
    order_id INT NOT NULL UNIQUE,
    shipping_method VARCHAR(50),
    tracking_number VARCHAR(100),
    carrier VARCHAR(50),
    shipping_cost DECIMAL(10,2),
    shipping_address JSON,
    estimated_delivery_date DATETIME,
    actual_delivery_date DATETIME,
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
);

-- PROMOTION USAGE
CREATE TABLE promotion_usage (
    usage_id INT PRIMARY KEY AUTO_INCREMENT,
    promotion_id INT NOT NULL,
    customer_id INT NOT NULL,
    order_id INT NOT NULL,
    used_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    discount_applied DECIMAL(10,2),
    FOREIGN KEY (promotion_id) REFERENCES promotions(promotion_id),
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

-- LOYALTY TRANSACTIONS
CREATE TABLE loyalty_transactions (
    transaction_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    order_id INT,
    return_id INT, -- defined later, but nullable
    points_change INT NOT NULL,
    transaction_type ENUM('Earned', 'Redeemed', 'Expired', 'Adjusted') NOT NULL,
    description VARCHAR(255),
    transaction_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATETIME,
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

-- 3. AUDIT & LOGGING
-- =============================================

CREATE TABLE inventory_log (
  log_id INT PRIMARY KEY AUTO_INCREMENT,
  product_id INT NOT NULL,
  quantity_change INT NOT NULL,
  transaction_type ENUM('ORDER', 'RESTOCK', 'ADJUSTMENT', 'RETURN') NOT NULL,
  transaction_subtype VARCHAR(50),
  reference_id INT, -- Flexible reference (Order ID, Restock Batch ID)
  reference_table VARCHAR(50),
  batch_id INT,
  previous_quantity INT,
  new_quantity INT,
  performed_by VARCHAR(100),
  notes TEXT,
  log_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (product_id) REFERENCES product(product_id)
);

CREATE TABLE low_stock_alerts (
  alert_id INT PRIMARY KEY AUTO_INCREMENT,
  product_id INT NOT NULL,
  alert_level ENUM('INFO', 'WARNING', 'CRITICAL'),
  current_quantity INT,
  reorder_point INT,
  message VARCHAR(255) NOT NULL,
  alert_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  resolved BOOLEAN DEFAULT FALSE,
  resolved_at DATETIME,
  resolution_notes TEXT,
  FOREIGN KEY (product_id) REFERENCES product(product_id)
);

CREATE TABLE system_error_log (
    error_id INT PRIMARY KEY AUTO_INCREMENT,
    error_code VARCHAR(50),
    mysql_errno INT,
    sql_state VARCHAR(10),
    error_message TEXT,
    stored_procedure VARCHAR(100),
    parameters JSON,
    severity ENUM('LOW', 'MEDIUM', 'HIGH', 'CRITICAL'),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE data_access_audit (
    audit_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id VARCHAR(100),
    action VARCHAR(50),
    table_name VARCHAR(50),
    record_id INT,
    old_values JSON,
    new_values JSON,
    ip_address VARCHAR(50),
    user_agent VARCHAR(255),
    occurred_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE business_rule_violations (
    violation_id INT PRIMARY KEY AUTO_INCREMENT,
    rule_name VARCHAR(100),
    violation_description TEXT,
    entity_type VARCHAR(50),
    entity_id INT,
    severity ENUM('WARNING', 'CRITICAL'),
    occurred_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- RETURNS MANAGEMENT (Advanced)
CREATE TABLE returns (
    return_id INT PRIMARY KEY AUTO_INCREMENT,
    return_number VARCHAR(50), -- Generated via trigger ideally
    order_id INT NOT NULL,
    customer_id INT NOT NULL,
    return_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    return_reason TEXT,
    return_status ENUM('Requested', 'Approved', 'Rejected', 'Completed', 'Refunded') DEFAULT 'Requested',
    refund_amount DECIMAL(10,2) DEFAULT 0,
    refund_method VARCHAR(50),
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id)
);

CREATE TABLE return_items (
    return_item_id INT PRIMARY KEY AUTO_INCREMENT,
    return_id INT NOT NULL,
    product_id INT NOT NULL,
    order_item_id INT NOT NULL,
    quantity_returned INT NOT NULL,
    conditions VARCHAR(50),
    restock_eligible BOOLEAN DEFAULT FALSE,
    restocked_quantity INT DEFAULT 0,
    unit_refund_amount DECIMAL(10,2),
    FOREIGN KEY (return_id) REFERENCES returns(return_id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES product(product_id)
);

-- =============================================
-- 4. OPTIMIZATION INDEXES
-- =============================================
CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date);
CREATE INDEX idx_product_category ON product(category_id);
CREATE INDEX idx_inventory_stock ON inventory(product_id, quantity_on_hand);
CREATE INDEX idx_log_reference ON inventory_log(reference_id, reference_table);
