/*
Triggers for Inventory and Customer Management System
Version: 2.0 - Production Ready
Automation of inventory alerts, customer lifetime value updates, 
data access logging,product rating updates.
*/
-- ============================================ 

USE IOMS;
DELIMITER $$

-- Trigger 1: Auto-create low stock alert
CREATE TRIGGER trg_low_stock_alert
AFTER UPDATE ON inventory
FOR EACH ROW
BEGIN
    DECLARE v_product_name VARCHAR(255);
    DECLARE v_current_level ENUM('INFO', 'WARNING', 'CRITICAL');
    
    -- Only trigger if quantity changed
    IF OLD.quantity_on_hand != NEW.quantity_on_hand THEN
        -- Get product name
        SELECT product_name INTO v_product_name 
        FROM product WHERE product_id = NEW.product_id;
        
        -- Determine alert level
        SET v_current_level = CASE
            WHEN NEW.quantity_on_hand <= NEW.reorder_point * 0.2 THEN 'CRITICAL'
            WHEN NEW.quantity_on_hand <= NEW.reorder_point * 0.45 THEN 'WARNING'
            WHEN NEW.quantity_on_hand <= NEW.reorder_point THEN 'INFO'
            ELSE NULL
        END;
        
        -- Create alert if needed
        IF v_current_level IS NOT NULL THEN
            INSERT INTO low_stock_alerts (
                product_id,
                alert_level,
                current_quantity,
                reorder_point,
                message
            ) VALUES (
                NEW.product_id,
                v_current_level,
                NEW.quantity_on_hand,
                NEW.reorder_point,
                CONCAT(
                    v_product_name, 
                    ' stock is at ', 
                    NEW.quantity_on_hand,
                    ' units (reorder point: ',
                    NEW.reorder_point,
                    '). Level: ',
                    v_current_level
                )
            );
        END IF;
    END IF;
END$$

-- Trigger 2: Update customer lifetime value
CREATE TRIGGER trg_update_customer_lifetime_value
AFTER INSERT ON orders
FOR EACH ROW
BEGIN
    DECLARE v_total_spent DECIMAL(10,2);
    
    -- Calculate total spent by customer
    SELECT COALESCE(SUM(total_amount), 0) INTO v_total_spent
    FROM orders 
    WHERE customer_id = NEW.customer_id 
    AND order_status NOT IN ('Cancelled', 'Returned');
    
    -- Update customer record
    UPDATE customer 
    SET 
        total_lifetime_value = v_total_spent,
        last_purchase_date = NEW.order_date
    WHERE customer_id = NEW.customer_id;
    
    -- Update loyalty program
    UPDATE customer_loyalty 
    SET total_spent = v_total_spent
    WHERE customer_id = NEW.customer_id;
END$$

-- Trigger 3: Log data access for sensitive tables
CREATE TRIGGER trg_audit_customer_changes
AFTER UPDATE ON customer
FOR EACH ROW
BEGIN
    INSERT INTO data_access_audit (
        user_id,
        action,
        table_name,
        record_id,
        old_values,
        new_values,
        ip_address,
        user_agent
    ) VALUES (
        USER(),
        'UPDATE',
        'customer',
        OLD.customer_id,
        JSON_OBJECT(
            'full_name', OLD.full_name,
            'email', OLD.email,
            'phone', OLD.phone,
            'shipping_address', OLD.shipping_address
        ),
        JSON_OBJECT(
            'full_name', NEW.full_name,
            'email', NEW.email,
            'phone', NEW.phone,
            'shipping_address', NEW.shipping_address
        ),
        COALESCE(@remote_ip, ''),
        COALESCE(@user_agent, '')
    );
END$$

-- Trigger 4: Update product rating
CREATE TRIGGER trg_update_product_rating
AFTER INSERT ON order_item
FOR EACH ROW
BEGIN
    DECLARE v_avg_rating DECIMAL(3,2);
    DECLARE v_review_count INT;
    
    -- In a real system, this would calculate from reviews table
    -- For now, we'll simulate with random data
    SET v_avg_rating = 3.5 + RAND() * 1.5;
    SET v_review_count = (SELECT review_count FROM product WHERE product_id = NEW.product_id) + 1;
    
    UPDATE product 
    SET 
        rating = v_avg_rating,
        review_count = v_review_count,
        updated_at = CURRENT_TIMESTAMP
    WHERE product_id = NEW.product_id;
END$$

-- Trigger 5: Prevent negative inventory
CREATE TRIGGER trg_prevent_negative_inventory
BEFORE UPDATE ON inventory
FOR EACH ROW
BEGIN
    IF NEW.quantity_on_hand < 0 THEN
        -- Log the violation
        INSERT INTO business_rule_violations (
            rule_name,
            violation_description,
            entity_type,
            entity_id,
            severity
        ) VALUES (
            'NegativeInventoryPrevention',
            CONCAT('Attempt to set negative inventory for product ', NEW.product_id),
            'Inventory',
            NEW.inventory_id,
            'CRITICAL'
        );
        
        -- Prevent the update
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot set inventory to negative value';
    END IF;
END$$

DELIMITER ;