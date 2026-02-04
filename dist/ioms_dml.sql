-- SAMPLE DATA POPULATION (Enhanced)
-- Populates core tables with realistic data for testing

-- 1. CATEGORIES
INSERT INTO product_category (category_name, description) VALUES 
('Electronics', 'Gadgets, computers, and accessories'),
('Apparel', 'Clothing, shoes, and wearables'),
('Books', 'Technical and non-fiction books'),
('Home & Garden', 'Furniture, decor, and tools');

-- 2. PRODUCTS
INSERT INTO product (product_name, category_id, sku, price, cost_price) VALUES
-- Electronics
('Smartphone X', 1, 'ELEC-PH-001', 500.00, 350.00),
('Laptop Pro 15', 1, 'ELEC-LP-001', 1200.00, 900.00),
('Wireless Headphones', 1, 'ELEC-AU-001', 150.00, 80.00),
('Monitor 27"', 1, 'ELEC-MN-001', 300.00, 200.00),
-- Apparel
('T-Shirt Classic', 2, 'APP-TS-001', 20.00, 5.00),
('Jeans Regular', 2, 'APP-JN-001', 40.00, 15.00),
('Running Shoes', 2, 'APP-SH-001', 85.00, 40.00),
-- Books
('Python Programming', 3, 'BK-CS-001', 45.00, 20.00),
('Data Science Guide', 3, 'BK-CS-002', 55.00, 25.00);

-- 3. INVENTORY (Initial Stock)
INSERT INTO inventory (product_id, quantity_on_hand, reorder_point, reorder_quantity) VALUES
(1, 50, 10, 20),
(2, 20, 5, 10),
(3, 100, 20, 50),
(4, 30, 8, 15),
(5, 200, 30, 100),
(6, 80, 20, 40),
(7, 60, 15, 30),
(8, 40, 10, 20),
(9, 35, 10, 20);

-- 4. SUPPLIERS
INSERT INTO suppliers (supplier_name, contact_email) VALUES 
('Tech Global Inc', 'sales@techglobal.com'),
('Fashion Wholesalers', 'orders@fashionwhole.com'),
('Book Publishers Ltd', 'distrib@books.com');

-- 5. PROMOTIONS
INSERT INTO promotions (promotion_code, promotion_name, promotion_type, discount_value, minimum_order_amount, valid_from, valid_to) VALUES
('WELCOME10', 'Welcome Discount', 'Percentage', 10.00, 0.00, NOW(), DATE_ADD(NOW(), INTERVAL 1 YEAR)),
('FREESHIP', 'Free Shipping over $100', 'Free Shipping', 0.00, 100.00, NOW(), DATE_ADD(NOW(), INTERVAL 1 YEAR)),
('SAVE50', 'Save $50 on Big Orders', 'Fixed Amount', 50.00, 500.00, NOW(), DATE_ADD(NOW(), INTERVAL 6 MONTH));

-- 6. CUSTOMERS
INSERT INTO customer (full_name, email, phone, shipping_address) VALUES
('John Doe', 'john@example.com', '123-456-7890', 'Kigali, Rwanda'),
('Jane Smith', 'jane@example.com', '098-765-4321', 'Musanze, Rwanda'),
('Alice Brown', 'alice@example.com', '555-555-5555', 'Huye, Rwanda');

-- Initialize Loyalty for customers
INSERT INTO customer_loyalty (customer_id) SELECT customer_id FROM customer;
-- Active: 1767084789057@@127.0.0.1@3306@ioms
-- Inventory and Order Management System (IOMS)
-- DML IMPLEMENTATION
-- Version: 2.0 - Production Ready
-- ADVANCED BUSINESS LOGIC PROCEDURES
-- ============================================

DELIMITER $$

-- 1. COMPLETE ORDER PLACEMENT PROCEDURE
CREATE PROCEDURE PlaceOrder(
    IN p_customer_id INT,
    IN p_order_items JSON,
    IN p_payment_method VARCHAR(50),
    IN p_shipping_method VARCHAR(50),
    IN p_shipping_address JSON,
    IN p_promotion_code VARCHAR(50),
    OUT p_order_id INT,
    OUT p_order_number VARCHAR(50),
    OUT p_status VARCHAR(50),
    OUT p_message TEXT
)
proc: BEGIN
    DECLARE v_customer_exists INT DEFAULT 0;
    DECLARE v_order_id INT;
    DECLARE v_order_number VARCHAR(50);
    DECLARE v_total_amount DECIMAL(10,2) DEFAULT 0;
    DECLARE v_subtotal DECIMAL(10,2) DEFAULT 0;
    DECLARE v_tax_amount DECIMAL(10,2) DEFAULT 0;
    DECLARE v_shipping_amount DECIMAL(10,2) DEFAULT 0;
    DECLARE v_discount_amount DECIMAL(10,2) DEFAULT 0;
    DECLARE v_promotion_id INT DEFAULT NULL;
    DECLARE v_item_count INT DEFAULT 0;
    DECLARE v_validation_error TEXT DEFAULT NULL;
    DECLARE v_invalid_product_id INT DEFAULT NULL;
    DECLARE v_insufficient_product_id INT DEFAULT NULL;
    DECLARE v_requested_qty INT DEFAULT 0;
    DECLARE v_available_qty INT DEFAULT 0;
    DECLARE v_inactive_product_id INT DEFAULT NULL;
    
    -- Temporary table for ordered items
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 
            @sqlstate = RETURNED_SQLSTATE,
            @errno = MYSQL_ERRNO,
            @text = MESSAGE_TEXT;
        
        -- Log error
        INSERT INTO system_error_log (
            error_code, 
            mysql_errno,
            sql_state,
            error_message, 
            stored_procedure, 
            parameters,
            severity
        ) VALUES (
            'ORDER_PLACEMENT_ERROR',
            @errno,
            @sqlstate,
            @text,
            'PlaceOrder',
            JSON_OBJECT(
                'customer_id', p_customer_id,
                'payment_method', p_payment_method,
                'shipping_method', p_shipping_method,
                'promotion_code', p_promotion_code
            ),
            'HIGH'
        );
        
        SET p_status = 'ERROR';
        SET p_message = CONCAT('Order placement failed: ', @text);
        ROLLBACK;
        RESIGNAL;
    END;
    
    -- 1. Validate JSON input
    IF JSON_VALID(p_order_items) = 0 OR p_order_items IS NULL OR p_order_items = '[]' THEN
        SET p_status = 'ERROR';
        SET p_message = 'Invalid or empty order items JSON';
        LEAVE proc;
    END IF;
    
    -- 2. Validate customer
    SELECT COUNT(*) INTO v_customer_exists 
    FROM customer 
    WHERE customer_id = p_customer_id AND is_active = TRUE;
    
    IF v_customer_exists = 0 THEN
        SET p_status = 'ERROR';
        SET p_message = CONCAT('Customer ID ', p_customer_id, ' does not exist or is inactive');
        LEAVE proc;
    END IF;
    
    -- 3. Create temporary table for order items
    CREATE TEMPORARY TABLE tmp_order_items (
        temp_id INT AUTO_INCREMENT PRIMARY KEY,
        product_id INT NOT NULL,
        quantity INT NOT NULL CHECK (quantity > 0),
        unit_price DECIMAL(10,2),
        product_name VARCHAR(255),
        is_active BOOLEAN,
        current_stock INT,
        validation_passed BOOLEAN DEFAULT FALSE,
        validation_message VARCHAR(255)
    ) ENGINE=MEMORY;
    
    -- 4. Parse JSON and validate products
    INSERT INTO tmp_order_items (product_id, quantity)
    SELECT 
        product_id,
        SUM(quantity) as quantity
    FROM JSON_TABLE(
        p_order_items,
        '$[*]' COLUMNS (
            product_id INT PATH '$.product_id',
            quantity INT PATH '$.quantity'
        )
    ) AS jt
    WHERE product_id IS NOT NULL AND quantity > 0
    GROUP BY product_id;
    
    SET v_item_count = ROW_COUNT();
    
    IF v_item_count = 0 THEN
        SET p_status = 'ERROR';
        SET p_message = 'No valid order items provided';
        DROP TEMPORARY TABLE tmp_order_items;
        LEAVE proc;
    END IF;
    
    -- 5. Update temporary table with product details
    UPDATE tmp_order_items t
    JOIN product p ON t.product_id = p.product_id
    JOIN inventory i ON t.product_id = i.product_id
    SET 
        t.unit_price = p.price,
        t.product_name = p.product_name,
        t.is_active = p.is_active,
        t.current_stock = i.quantity_available;
    
    -- 6. Validate all items
    -- Check for invalid products
    SELECT product_id INTO v_invalid_product_id
    FROM tmp_order_items
    WHERE unit_price IS NULL
    LIMIT 1;
    
    IF v_invalid_product_id IS NOT NULL THEN
        SET p_status = 'ERROR';
        SET p_message = CONCAT('Product ID ', v_invalid_product_id, ' does not exist');
        DROP TEMPORARY TABLE tmp_order_items;
        LEAVE proc;
    END IF;
    
    -- Check for inactive products
    SELECT product_id INTO v_inactive_product_id
    FROM tmp_order_items
    WHERE is_active = FALSE
    LIMIT 1;
    
    IF v_inactive_product_id IS NOT NULL THEN
        SET p_status = 'ERROR';
        SET p_message = CONCAT('Product ID ', v_inactive_product_id, ' is inactive');
        DROP TEMPORARY TABLE tmp_order_items;
        LEAVE proc;
    END IF;
    
    -- Check stock availability
    SELECT product_id, quantity, current_stock 
    INTO v_insufficient_product_id, v_requested_qty, v_available_qty
    FROM tmp_order_items
    WHERE current_stock < quantity
    LIMIT 1;
    
    IF v_insufficient_product_id IS NOT NULL THEN
        SET p_status = 'ERROR';
        SET p_message = CONCAT(
            'Insufficient stock for Product ID ', v_insufficient_product_id,
            '. Requested: ', v_requested_qty,
            ', Available: ', v_available_qty
        );
        DROP TEMPORARY TABLE tmp_order_items;
        LEAVE proc;
    END IF;
    
    -- 7. Calculate order amounts
    SELECT 
        SUM(quantity * unit_price) INTO v_subtotal
    FROM tmp_order_items;
    
    -- Calculate tax (simplified - 18% tax)
    SET v_tax_amount = v_subtotal * 0.18;
    
    -- Calculate shipping (simplified - fixed based on method)
    SET v_shipping_amount = CASE p_shipping_method
        WHEN 'STANDARD' THEN 5.00
        WHEN 'EXPRESS' THEN 15.00
        WHEN 'OVERNIGHT' THEN 25.00
        ELSE 10.00
    END;
    
    -- Apply promotion if valid
    IF p_promotion_code IS NOT NULL THEN
        SELECT promotion_id INTO v_promotion_id
        FROM promotions
        WHERE promotion_code = p_promotion_code
        AND is_active = TRUE
        AND valid_from <= NOW()
        AND valid_to >= NOW()
        AND (max_uses_total IS NULL OR times_used < max_uses_total)
        AND (v_subtotal >= minimum_order_amount OR minimum_order_amount = 0);
        
        IF v_promotion_id IS NOT NULL THEN
            -- Calculate discount based on promotion type
            SET v_discount_amount = CASE (SELECT promotion_type FROM promotions WHERE promotion_id = v_promotion_id)
                WHEN 'Percentage' THEN LEAST(v_subtotal * (SELECT discount_value FROM promotions WHERE promotion_id = v_promotion_id) / 100, 
                                            COALESCE((SELECT maximum_discount_amount FROM promotions WHERE promotion_id = v_promotion_id), v_subtotal))
                WHEN 'Fixed Amount' THEN (SELECT discount_value FROM promotions WHERE promotion_id = v_promotion_id)
                WHEN 'Free Shipping' THEN v_shipping_amount
                ELSE 0
            END;
            
            -- For free shipping, set shipping to 0
            IF (SELECT promotion_type FROM promotions WHERE promotion_id = v_promotion_id) = 'Free Shipping' THEN
                SET v_shipping_amount = 0;
            END IF;
        END IF;
    END IF;
    
    -- Calculate total
    SET v_total_amount = v_subtotal + v_tax_amount + v_shipping_amount - v_discount_amount;
    
    -- 8. Start transaction
    START TRANSACTION;
    
    -- 9. Lock inventory rows for update
    SELECT i.product_id
    FROM inventory i
    JOIN tmp_order_items t ON i.product_id = t.product_id
    ORDER BY i.product_id
    FOR UPDATE;
    
    -- 10. Create order header
    INSERT INTO orders (
        customer_id,
        order_date,
        total_amount,
        subtotal,
        tax_amount,
        shipping_amount,
        discount_amount,
        payment_method,
        payment_status,
        shipping_method,
        order_status
    ) VALUES (
        p_customer_id,
        NOW(),
        v_total_amount,
        v_subtotal,
        v_tax_amount,
        v_shipping_amount,
        v_discount_amount,
        p_payment_method,
        'Pending',
        p_shipping_method,
        'Pending'
    );
    
    SET v_order_id = LAST_INSERT_ID();
    SET v_order_number = (SELECT order_number FROM orders WHERE order_id = v_order_id);
    
    -- 11. Insert order items
    INSERT INTO order_item (
        order_id,
        product_id,
        quantity,
        unit_price
    )
    SELECT 
        v_order_id,
        product_id,
        quantity,
        unit_price
    FROM tmp_order_items;
    
    -- 12. Update inventory
    UPDATE inventory i
    JOIN tmp_order_items t ON i.product_id = t.product_id
    SET 
        i.quantity_reserved = i.quantity_reserved + t.quantity,
        i.last_sale_date = NOW(),
        i.last_updated = NOW();
    
    -- 13. Log inventory movements
    INSERT INTO inventory_log (
        product_id,
        quantity_change,
        transaction_type,
        reference_id,
        reference_table,
        previous_quantity,
        new_quantity,
        performed_by
    )
    SELECT 
        t.product_id,
        -t.quantity,
        'ORDER',
        v_order_id,
        'orders',
        i.quantity_on_hand + i.quantity_reserved,
        i.quantity_on_hand + i.quantity_reserved - t.quantity,
        CONCAT('Customer:', p_customer_id)
    FROM tmp_order_items t
    JOIN inventory i ON t.product_id = i.product_id;
    
    -- 14. Record promotion usage
    IF v_promotion_id IS NOT NULL THEN
        INSERT INTO promotion_usage (
            promotion_id,
            customer_id,
            order_id,
            discount_applied
        ) VALUES (
            v_promotion_id,
            p_customer_id,
            v_order_id,
            v_discount_amount
        );
        
        -- Update promotion usage count
        UPDATE promotions 
        SET times_used = times_used + 1
        WHERE promotion_id = v_promotion_id;
    END IF;
    
    -- 15. Create shipping info
    INSERT INTO shipping_info (
        order_id,
        shipping_method,
        shipping_cost,
        shipping_address,
        estimated_delivery_date
    ) VALUES (
        v_order_id,
        p_shipping_method,
        v_shipping_amount,
        p_shipping_address,
        DATE_ADD(NOW(), INTERVAL 
            CASE p_shipping_method
                WHEN 'STANDARD' THEN 7
                WHEN 'EXPRESS' THEN 3
                WHEN 'OVERNIGHT' THEN 1
                ELSE 5
            END DAY)
    );
    
    -- 16. Update customer loyalty points (1 point per $10 spent)
    IF v_total_amount > 0 THEN
        INSERT INTO loyalty_transactions (
            customer_id,
            order_id,
            points_change,
            transaction_type,
            description,
            expiry_date
        ) VALUES (
            p_customer_id,
            v_order_id,
            FLOOR(v_total_amount / 10),
            'Earned',
            CONCAT('Points earned for order ', v_order_number),
            DATE_ADD(NOW(), INTERVAL 365 DAY)
        );
        
        UPDATE customer_loyalty 
        SET 
            loyalty_points = loyalty_points + FLOOR(v_total_amount / 10),
            points_earned = points_earned + FLOOR(v_total_amount / 10),
            total_spent = total_spent + v_total_amount
        WHERE customer_id = p_customer_id;
    END IF;
    
    -- 17. Commit transaction
    COMMIT;
    
    -- 18. Set output parameters
    SET p_order_id = v_order_id;
    SET p_order_number = v_order_number;
    SET p_status = 'SUCCESS';
    SET p_message = CONCAT('Order ', v_order_number, ' placed successfully. Total: $', v_total_amount);
    
    -- 19. Cleanup
    DROP TEMPORARY TABLE tmp_order_items;
    
    -- 20. Return success details
    SELECT 
        p_status as status,
        p_message as message,
        p_order_id as order_id,
        p_order_number as order_number,
        v_subtotal as subtotal,
        v_tax_amount as tax,
        v_shipping_amount as shipping,
        v_discount_amount as discount,
        v_total_amount as total;
    
END proc$$

-- 2. INVENTORY RESTOCK PROCEDURE
CREATE PROCEDURE RestockInventory(
    IN p_product_id INT,
    IN p_quantity INT,
    IN p_batch_number VARCHAR(50),
    IN p_supplier_id INT,
    IN p_unit_cost DECIMAL(10,2),
    IN p_expiration_date DATE,
    OUT p_status VARCHAR(50),
    OUT p_message TEXT
)
proc:BEGIN
    DECLARE v_product_exists INT DEFAULT 0;
    DECLARE v_supplier_exists INT DEFAULT 0;
    DECLARE v_batch_id INT;
    DECLARE v_previous_quantity INT;
    DECLARE v_new_quantity INT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_status = 'ERROR';
        SET p_message = CONCAT('Restock failed: ', ERROR_MESSAGE());
        ROLLBACK;
    END;
    
    -- Validate inputs
    IF p_quantity <= 0 THEN
        SET p_status = 'ERROR';
        SET p_message = 'Quantity must be greater than 0';
        LEAVE proc;
    END IF;
    
    IF p_unit_cost <= 0 THEN
        SET p_status = 'ERROR';
        SET p_message = 'Unit cost must be greater than 0';
        LEAVE proc;
    END IF;
    
    -- Validate product
    SELECT COUNT(*) INTO v_product_exists 
    FROM product 
    WHERE product_id = p_product_id AND is_active = TRUE;
    
    IF v_product_exists = 0 THEN
        SET p_status = 'ERROR';
        SET p_message = CONCAT('Product ID ', p_product_id, ' does not exist or is inactive');
        LEAVE proc;
    END IF;
    
    -- Validate supplier
    IF p_supplier_id IS NOT NULL THEN
        SELECT COUNT(*) INTO v_supplier_exists 
        FROM suppliers 
        WHERE supplier_id = p_supplier_id AND is_active = TRUE;
        
        IF v_supplier_exists = 0 THEN
            SET p_status = 'ERROR';
            SET p_message = CONCAT('Supplier ID ', p_supplier_id, ' does not exist or is inactive');
            LEAVE proc;
        END IF;
    END IF;
    
    START TRANSACTION;
    
    -- Get current quantity
    SELECT quantity_on_hand INTO v_previous_quantity
    FROM inventory 
    WHERE product_id = p_product_id
    FOR UPDATE;
    
    -- Create inventory batch record
    IF p_batch_number IS NOT NULL THEN
        INSERT INTO inventory_batch (
            product_id,
            batch_number,
            quantity_received,
            quantity_remaining,
            unit_cost,
            expiration_date,
            supplier_id,
            received_date
        ) VALUES (
            p_product_id,
            p_batch_number,
            p_quantity,
            p_quantity,
            p_unit_cost,
            p_expiration_date,
            p_supplier_id,
            NOW()
        );
        
        SET v_batch_id = LAST_INSERT_ID();
    END IF;
    
    -- Update inventory
    UPDATE inventory 
    SET 
        quantity_on_hand = quantity_on_hand + p_quantity,
        last_restock_date = NOW(),
        last_updated = NOW()
    WHERE product_id = p_product_id;
    
    -- Get new quantity
    SELECT quantity_on_hand INTO v_new_quantity
    FROM inventory 
    WHERE product_id = p_product_id;
    
    -- Log inventory movement
    INSERT INTO inventory_log (
        product_id,
        quantity_change,
        transaction_type,
        transaction_subtype,
        reference_id,
        reference_table,
        batch_id,
        previous_quantity,
        new_quantity,
        performed_by,
        notes
    ) VALUES (
        p_product_id,
        p_quantity,
        'RESTOCK',
        'PURCHASE',
        v_batch_id,
        'inventory_batch',
        v_batch_id,
        v_previous_quantity,
        v_new_quantity,
        USER(),
        CONCAT('Restocked ', p_quantity, ' units')
    );
    
    -- Resolve any low stock alerts for this product
    UPDATE low_stock_alerts 
    SET 
        resolved = TRUE,
        resolved_at = NOW(),
        resolution_notes = CONCAT('Resolved by restock of ', p_quantity, ' units')
    WHERE product_id = p_product_id 
    AND resolved = FALSE;
    
    COMMIT;
    
    SET p_status = 'SUCCESS';
    SET p_message = CONCAT(
        'Successfully restocked ', p_quantity, ' units of product ', p_product_id,
        '. New stock level: ', v_new_quantity
    );
    
    SELECT p_status as status, p_message as message;
    
END proc$$


-- 3. PROCESS RETURN PROCEDURE
CREATE PROCEDURE ProcessReturn(
    IN p_order_id INT,
    IN p_return_items JSON,
    IN p_return_reason VARCHAR(50),
    IN p_refund_method VARCHAR(50),
    OUT p_return_id INT,
    OUT p_status VARCHAR(50),
    OUT p_message TEXT
)
proc:BEGIN
    DECLARE v_order_exists INT DEFAULT 0;
    DECLARE v_customer_id INT;
    DECLARE v_order_total DECIMAL(10,2);
    DECLARE v_return_total DECIMAL(10,2) DEFAULT 0;
    DECLARE v_item_count INT DEFAULT 0;
    DECLARE v_return_number VARCHAR(50);
    DECLARE v_invalid_item INT DEFAULT NULL;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_status = 'ERROR';
        SET p_message = CONCAT('Return processing failed: ', ERROR_MESSAGE());
        ROLLBACK;
    END;
    
    -- Validate order
    SELECT COUNT(*), customer_id, total_amount 
    INTO v_order_exists, v_customer_id, v_order_total
    FROM orders 
    WHERE order_id = p_order_id 
    AND order_status NOT IN ('Cancelled', 'Returned');
    
    IF v_order_exists = 0 THEN
        SET p_status = 'ERROR';
        SET p_message = CONCAT('Order ID ', p_order_id, ' does not exist or cannot be returned');
        LEAVE proc;
    END IF;
    
    -- Validate JSON
    IF JSON_VALID(p_return_items) = 0 THEN
        SET p_status = 'ERROR';
        SET p_message = 'Invalid return items JSON';
        LEAVE proc;
    END IF;
    
    -- Create temporary table for return items
    CREATE TEMPORARY TABLE tmp_return_items (
        temp_id INT AUTO_INCREMENT PRIMARY KEY,
        order_item_id INT NOT NULL,
        product_id INT NOT NULL,
        quantity_returned INT NOT NULL CHECK (quantity_returned > 0),
        original_quantity INT,
        unit_price DECIMAL(10,2),
        conditions VARCHAR(50),
        restock_eligible BOOLEAN DEFAULT FALSE,
        max_returnable INT
    ) ENGINE=MEMORY;
    
    -- Parse and validate return items
    INSERT INTO tmp_return_items (order_item_id, product_id, quantity_returned, conditions)
    SELECT 
        oi.order_item_id,
        oi.product_id,
        jt.quantity,
        jt.condition
    FROM JSON_TABLE(
        p_return_items,
        '$[*]' COLUMNS (
            order_item_id INT PATH '$.order_item_id',
            quantity INT PATH '$.quantity',
            conditions VARCHAR(50) PATH '$.condition'
        )
    ) AS jt
    JOIN order_item oi ON jt.order_item_id = oi.order_item_id
    WHERE oi.order_id = p_order_id;
    
    SET v_item_count = ROW_COUNT();
    
    IF v_item_count = 0 THEN
        SET p_status = 'ERROR';
        SET p_message = 'No valid return items provided';
        DROP TEMPORARY TABLE tmp_return_items;
        LEAVE proc;
    END IF;
    
    -- Get original order details
    UPDATE tmp_return_items t
    JOIN order_item oi ON t.order_item_id = oi.order_item_id
    SET 
        t.original_quantity = oi.quantity,
        t.unit_price = oi.unit_price_at_purchase,
        t.max_returnable = oi.quantity;
    
    -- Validate quantities
    SELECT order_item_id INTO v_invalid_item
    FROM tmp_return_items
    WHERE quantity_returned > max_returnable
    LIMIT 1;
    
    IF v_invalid_item IS NOT NULL THEN
        SET p_status = 'ERROR';
        SET p_message = CONCAT('Cannot return more than originally purchased for item ', v_invalid_item);
        DROP TEMPORARY TABLE tmp_return_items;
        LEAVE proc;
    END IF;
    
    -- Determine restock eligibility
    UPDATE tmp_return_items
    SET restock_eligible = CASE 
        WHEN conditions IN ('New', 'Opened') THEN TRUE
        ELSE FALSE
    END;
    
    -- Calculate return total
    SELECT SUM(quantity_returned * unit_price) INTO v_return_total
    FROM tmp_return_items;
    
    START TRANSACTION;
    
    -- Create return record
    INSERT INTO returns (
        order_id,
        customer_id,
        return_date,
        return_reason,
        return_status,
        refund_amount,
        refund_method
    ) VALUES (
        p_order_id,
        v_customer_id,
        NOW(),
        p_return_reason,
        'Requested',
        v_return_total,
        p_refund_method
    );
    
    SET p_return_id = LAST_INSERT_ID();
    SET v_return_number = (SELECT return_number FROM returns WHERE return_id = p_return_id);
    
    -- Insert return items
    INSERT INTO return_items (
        return_id,
        product_id,
        order_item_id,
        quantity_returned,
        conditions,
        restock_eligible,
        unit_refund_amount
    )
    SELECT 
        p_return_id,
        product_id,
        order_item_id,
        quantity_returned,
        conditions,
        restock_eligible,
        unit_price
    FROM tmp_return_items;
    
    -- Update order status
    UPDATE orders 
    SET order_status = 'Returned'
    WHERE order_id = p_order_id;
    
    -- Restock inventory for eligible items
    UPDATE inventory i
    JOIN (
        SELECT product_id, SUM(quantity_returned) as total_returned
        FROM tmp_return_items
        WHERE restock_eligible = TRUE
        GROUP BY product_id
    ) t ON i.product_id = t.product_id
    SET 
        i.quantity_on_hand = i.quantity_on_hand + t.total_returned,
        i.last_updated = NOW();
    
    -- Log inventory movements for restocked items
    INSERT INTO inventory_log (
        product_id,
        quantity_change,
        transaction_type,
        transaction_subtype,
        reference_id,
        reference_table,
        performed_by,
        notes
    )
    SELECT 
        t.product_id,
        t.total_returned,
        'ADJUSTMENT',
        'RETURN_RESTOCK',
        p_return_id,
        'returns',
        USER(),
        CONCAT('Return restock from order ', p_order_id)
    FROM (
        SELECT product_id, SUM(quantity_returned) as total_returned
        FROM tmp_return_items
        WHERE restock_eligible = TRUE
        GROUP BY product_id
    ) t;
    
    -- Update return items with restocked quantities
    UPDATE return_items ri
    JOIN tmp_return_items t ON ri.return_item_id = LAST_INSERT_ID() - (v_item_count - t.temp_id)
    SET ri.restocked_quantity = CASE 
        WHEN t.restock_eligible = TRUE THEN t.quantity_returned
        ELSE 0
    END;
    
    -- Update customer loyalty (deduct points for returns)
    IF v_return_total > 0 THEN
        INSERT INTO loyalty_transactions (
            customer_id,
            return_id,
            points_change,
            transaction_type,
            description
        ) VALUES (
            v_customer_id,
            p_return_id,
            -FLOOR(v_return_total / 10),
            'Adjusted',
            CONCAT('Points adjusted for return ', v_return_number)
        );
        
        UPDATE customer_loyalty 
        SET 
            loyalty_points = loyalty_points - FLOOR(v_return_total / 10),
            points_redeemed = points_redeemed + FLOOR(v_return_total / 10)
        WHERE customer_id = v_customer_id;
    END IF;
    
    COMMIT;
    
    SET p_status = 'SUCCESS';
    SET p_message = CONCAT(
        'Return ', v_return_number, ' processed successfully. ',
        'Refund amount: $', v_return_total
    );
    
    DROP TEMPORARY TABLE tmp_return_items;
    
    SELECT p_status as status, p_message as message, p_return_id as return_id, v_return_number as return_number;
    
END proc$$



-- 4. UPDATE CUSTOMER LOYALTY TIERS
CREATE PROCEDURE UpdateCustomerLoyaltyTiers()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_customer_id INT;
    DECLARE v_total_spent DECIMAL(10,2);
    DECLARE v_current_tier VARCHAR(20);
    DECLARE v_new_tier VARCHAR(20);
    
    DECLARE cur_customers CURSOR FOR
        SELECT cl.customer_id, cl.total_spent, cl.loyalty_tier
        FROM customer_loyalty cl;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN cur_customers;
    
    read_loop: LOOP
        FETCH cur_customers INTO v_customer_id, v_total_spent, v_current_tier;
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        -- Determine new tier based on total spent
        SET v_new_tier = CASE
            WHEN v_total_spent >= 5000 THEN 'Platinum'
            WHEN v_total_spent >= 2000 THEN 'Gold'
            WHEN v_total_spent >= 500 THEN 'Silver'
            ELSE 'Bronze'
        END;
        
        -- Update if tier changed
        IF v_new_tier != v_current_tier THEN
            UPDATE customer_loyalty
            SET 
                loyalty_tier = v_new_tier,
                tier_effective_date = CURDATE(),
                next_tier_threshold = CASE v_new_tier
                    WHEN 'Bronze' THEN 500
                    WHEN 'Silver' THEN 2000
                    WHEN 'Gold' THEN 5000
                    ELSE NULL
                END
            WHERE customer_id = v_customer_id;
            
            -- Log tier upgrade
            INSERT INTO loyalty_transactions (
                customer_id,
                points_change,
                transaction_type,
                description
            ) VALUES (
                v_customer_id,
                0,
                'Tier Upgrade',
                CONCAT('Upgraded from ', v_current_tier, ' to ', v_new_tier)
            );
        END IF;
    END LOOP;
    
    CLOSE cur_customers;
    
    SELECT 'Customer loyalty tiers updated successfully' as status;
    
END$$

DELIMITER ;


-- MONITORING AND MAINTENANCE PROCEDURES
-- ============================================

DELIMITER $$

-- 1. SYSTEM HEALTH CHECK
CREATE PROCEDURE CheckSystemHealth()
BEGIN
    -- Database size
    SELECT 
        'DATABASE_SIZE' as check_type,
        ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as size_mb,
        COUNT(*) as table_count
    FROM information_schema.tables 
    WHERE table_schema = 'IOM';
    
    -- Table sizes
    SELECT 
        'TABLE_SIZES' as check_type,
        table_name,
        ROUND((data_length + index_length) / 1024 / 1024, 2) as size_mb,
        table_rows
    FROM information_schema.tables 
    WHERE table_schema = 'IOM'
    ORDER BY (data_length + index_length) DESC
    LIMIT 10;
    
    -- Unresolved errors
    SELECT 
        'UNRESOLVED_ERRORS' as check_type,
        COUNT(*) as error_count,
        severity,
        MIN(error_time) as oldest_error,
        MAX(error_time) as latest_error
    FROM system_error_log
    WHERE resolved = FALSE
    GROUP BY severity;
    
    -- Active alerts
    SELECT 
        'ACTIVE_ALERTS' as check_type,
        COUNT(*) as alert_count,
        alert_level,
        MIN(alert_date) as oldest_alert,
        MAX(alert_date) as latest_alert
    FROM low_stock_alerts
    WHERE resolved = FALSE
    GROUP BY alert_level;
    
    -- Index fragmentation (simplified)
    SELECT 
        'INDEX_HEALTH' as check_type,
        table_name,
        index_name,
        ROUND(cardinality / NULLIF(table_rows, 0) * 100, 2) as selectivity_percent
    FROM information_schema.statistics 
    WHERE table_schema = 'IOM'
    AND cardinality IS NOT NULL
    AND table_rows > 1000
    ORDER BY selectivity_percent
    LIMIT 10;
    
END$$


-- 4. INVENTORY HEALTH CHECK
CREATE PROCEDURE CheckInventoryHealth()
BEGIN
    -- Critical Stock Analysis
    SELECT 
        'CRITICAL_STOCK' as analysis_type,
        p.product_id,
        p.product_name,
        p.sku,
        pc.category_name,
        i.quantity_on_hand,
        i.quantity_available,
        i.reorder_point,
        i.reorder_quantity,
        CASE 
            WHEN i.quantity_available <= 0 THEN 'OUT_OF_STOCK'
            WHEN i.quantity_available <= i.reorder_point THEN 'BELOW_REORDER'
            WHEN i.quantity_available <= i.reorder_point * 2 THEN 'LOW_STOCK'
            ELSE 'HEALTHY'
        END as stock_status,
        DATEDIFF(CURDATE(), i.last_restock_date) as days_since_restock,
        COALESCE((
            SELECT SUM(quantity_ordered - quantity_received) 
            FROM purchase_order_items poi
            JOIN purchase_orders po ON poi.po_id = po.po_id
            WHERE poi.product_id = p.product_id 
            AND po.status IN ('Ordered', 'Partial')
        ), 0) as quantity_on_order,
        COALESCE((
            SELECT AVG(oi.quantity) 
            FROM order_item oi
            JOIN orders o ON oi.order_id = o.order_id
            WHERE oi.product_id = p.product_id
            AND o.order_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
        ), 0) as avg_daily_sales,
        CASE 
            WHEN i.quantity_available <= 0 THEN 0
            WHEN COALESCE((
                SELECT AVG(oi.quantity) 
                FROM order_item oi
                JOIN orders o ON oi.order_id = o.order_id
                WHERE oi.product_id = p.product_id
                AND o.order_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
            ), 0) = 0 THEN 999
            ELSE FLOOR(i.quantity_available / (
                SELECT AVG(oi.quantity) 
                FROM order_item oi
                JOIN orders o ON oi.order_id = o.order_id
                WHERE oi.product_id = p.product_id
                AND o.order_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
            ))
        END as days_of_inventory
    FROM product p
    JOIN product_category pc ON p.category_id = pc.category_id
    JOIN inventory i ON p.product_id = i.product_id
    WHERE p.is_active = TRUE
    AND i.quantity_available <= i.reorder_point * 2
    ORDER BY i.quantity_available ASC;
    
    -- Slow Moving Inventory
    SELECT 
        'SLOW_MOVING' as analysis_type,
        p.product_id,
        p.product_name,
        p.sku,
        pc.category_name,
        i.quantity_on_hand,
        i.quantity_available,
        COALESCE(SUM(oi.quantity), 0) as last_90_days_sales,
        i.last_sale_date,
        DATEDIFF(CURDATE(), i.last_sale_date) as days_since_last_sale,
        ROUND(i.quantity_on_hand / NULLIF(COALESCE(SUM(oi.quantity), 0), 0), 2) as months_of_supply
    FROM product p
    JOIN product_category pc ON p.category_id = pc.category_id
    JOIN inventory i ON p.product_id = i.product_id
    LEFT JOIN order_item oi ON p.product_id = oi.product_id
    LEFT JOIN orders o ON oi.order_id = o.order_id
        AND o.order_date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
        AND o.order_status NOT IN ('Cancelled', 'Returned')
    WHERE p.is_active = TRUE
    AND i.quantity_on_hand > 0
    GROUP BY p.product_id, p.product_name, p.sku, pc.category_name, i.quantity_on_hand, i.quantity_available, i.last_sale_date
    HAVING COALESCE(SUM(oi.quantity), 0) = 0 
        OR DATEDIFF(CURDATE(), i.last_sale_date) > 90
    ORDER BY days_since_last_sale DESC;
END$$


-- 2. PERFORMANCE OPTIMIZATION
CREATE PROCEDURE OptimizePerformance()
BEGIN
    -- Analyze tables for query optimization
    ANALYZE TABLE 
        customer, 
        product, 
        orders, 
        order_item, 
        inventory, 
        inventory_log,
        returns,
        customer_loyalty;
    
    -- Optimize fragmented tables
    OPTIMIZE TABLE 
        order_item, 
        inventory_log,
        system_error_log,
        query_performance_log;
    
    -- Clear old performance logs
    DELETE FROM query_performance_log 
    WHERE timestamp < DATE_SUB(CURDATE(), INTERVAL 7 DAY);
    
    DELETE FROM active_connections_log 
    WHERE logged_at < DATE_SUB(CURDATE(), INTERVAL 1 DAY);
    
    -- Update statistics
    FLUSH STATUS;
    FLUSH TABLES;
    
    SELECT 'Performance optimization completed' as status;
    
END$$

-- 3. DATA INTEGRITY CHECK
CREATE PROCEDURE CheckDataIntegrity()
BEGIN
    -- Orphaned order items
    SELECT 
        'ORPHANED_ORDER_ITEMS' as issue_type,
        COUNT(*) as count
    FROM order_item oi
    LEFT JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_id IS NULL;
    
    -- Orphaned inventory records
    SELECT 
        'ORPHANED_INVENTORY' as issue_type,
        COUNT(*) as count
    FROM inventory i
    LEFT JOIN product p ON i.product_id = p.product_id
    WHERE p.product_id IS NULL;
    
    -- Negative inventory (should never happen)
    SELECT 
        'NEGATIVE_INVENTORY' as issue_type,
        COUNT(*) as count
    FROM inventory
    WHERE quantity_on_hand < 0 OR quantity_reserved < 0;
    
    -- Inactive products with inventory
    SELECT 
        'INACTIVE_PRODUCTS_WITH_STOCK' as issue_type,
        COUNT(*) as count
    FROM product p
    JOIN inventory i ON p.product_id = i.product_id
    WHERE p.is_active = FALSE
    AND (i.quantity_on_hand > 0 OR i.quantity_reserved > 0);
    
    -- Customers with invalid emails
    SELECT 
        'INVALID_CUSTOMER_EMAILS' as issue_type,
        COUNT(*) as count
    FROM customer
    WHERE email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';
    
    -- Orders with mismatched totals
    SELECT 
        'ORDERS_TOTAL_MISMATCH' as issue_type,
        COUNT(*) as count
    FROM orders o
    JOIN (
        SELECT order_id, 
               SUM(quantity * unit_price) as calculated_total
        FROM order_item
        GROUP BY order_id
    ) oi ON o.order_id = oi.order_id
    WHERE ABS(o.total_amount - oi.calculated_total) > 0.01;
    
END$$

DELIMITER ;

-- EXAMPLE USAGE AND TESTING
-- ============================================

-- Test PlaceOrder
/*
SET @customer_id = 1;
SET @order_items = '[{"product_id": 1, "quantity": 2}, {"product_id": 2, "quantity": 1}]';
SET @payment_method = 'Credit Card';
SET @shipping_method = 'EXPRESS';
SET @shipping_address = '{"address": "123 Main St", "city": "Kigali", "country": "Rwanda"}';
SET @promotion_code = 'WELCOME10';

CALL PlaceOrder(
    @customer_id,
    @order_items,
    @payment_method,
    @shipping_method,
    @shipping_address,
    @promotion_code,
    @order_id,
    @order_number,
    @status,
    @message
);

SELECT @order_id, @order_number, @status, @message;
*/

-- Test RestockInventory
/*
SET @product_id = 1;
SET @quantity = 100;
SET @batch_number = 'BATCH123';
SET @supplier_id = 1;
SET @unit_cost = 10.00;
SET @expiration_date = '2025-12-31';
CALL RestockInventory(
    @product_id,   
    @quantity,
    @batch_number,
    @supplier_id,
    @unit_cost,
    @expiration_date,
    @status,
    @message
);

SELECT @status, @message;
*/

-- Test
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
