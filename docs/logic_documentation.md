# Business Logic Documentation

This document provides a technical overview of the **Stored Procedures** and **Triggers** implemented in the IOMS system. These database objects enforce business rules, ensure data integrity, and automate key workflows.

## Table of Contents
1.  [Stored Procedures](#stored-procedures)
    *   [PlaceOrder](#placeorder)
    *   [RestockInventory](#restockinventory)
    *   [ProcessReturn](#processreturn)
    *   [Maintenance Procedures](#maintenance-procedures)
2.  [Triggers](#triggers)
    *   [Low Stock Alerts](#trg_low_stock_alert)
    *   [Customer Lifetime Value](#trg_update_customer_lifetime_value)
    *   [Audit Logging](#trg_audit_customer_changes)
    *   [Inventory Safeguards](#trg_prevent_negative_inventory)

---

## Stored Procedures

### `PlaceOrder`
**Purpose**: Handles the complex logic of creating a sales order, ensuring inventory availability, calculating totals/discounts, and maintaining ACID compliance.

**Parameters**:
- `IN p_customer_id`: ID of the purchasing customer.
- `IN p_order_items`: JSON array of items (e.g., `[{"product_id": 1, "quantity": 2}]`).
- `IN p_payment_method`: Method of payment.
- `IN p_shipping_method`: Selected shipping option.
- `IN p_shipping_address`: JSON object for delivery address.
- `IN p_promotion_code`: (Optional) Coupon code to apply.
- `OUT p_order_id`, `p_order_number`, `p_status`, `p_message`: Return values for the application.

**Key Logic (Set-Based Efficiency)**:
1.  **Bulk Parsing (The "Gathering" Phase)**: Instead of looping, uses `JSON_TABLE` to instantly convert the entire input JSON array into a temporary table (`tmp_order_items`). This allows processing 50+ items as a single set.
2.  **Batch Validation**: Validates all items simultaneously. Updates prices, names, and checks stock for the entire batch in single set-based queries.
3.  **Concurrency Control**: Uses `SELECT ... FOR UPDATE` to lock inventory rows for *all* products in the order at once. This prevents deadlocks and race conditions.
4.  **Atomic Bulk Execution**: Performs insertions (`INSERT INTO ... SELECT`) and inventory updates for all items in a single transaction. If any item fails, the entire order is rolled back.

### `RestockInventory`
**Purpose**: Manages the reception of new stock from suppliers.

**Parameters**:
- `IN p_product_id`: Product being restocked.
- `IN p_quantity`: Amount received.
- `IN p_batch_number`: Supplier batch code.
- `IN p_supplier_id`: Source supplier.
- `IN p_unit_cost`: Cost per unit for this batch.
- `IN p_expiration_date`: (Optional) Expiry for perishable goods.

**Key Logic**:
1.  **Validation**: Ensures positive quantities and valid product/supplier IDs.
2.  **Batch Tracking**: Creates an entry in `inventory_batch` for traceability.
3.  **Inventory Update**: Increments `quantity_on_hand` and updates `last_restock_date`.
4.  **Alert resolution**: Automatically resolves any open "Low Stock" alerts for this product.

### `ProcessReturn`
**Purpose**: Handles customer product returns and refunds.

**Key Logic**:
1.  **Batch Processing**: Uses `JSON_TABLE` to handle multiple return items efficiently in a single pass, similar to `PlaceOrder`.
2.  **Validation**: Verifies order existence and that return quantities do not exceed original purchase quantities for any item in the batch.
3.  **Execution**:
    *   Verifies return quantity does not exceed purchased quantity.
    *   Calculates refund amount.
    *   **Conditional Restock**: If items are marked 'Restock Eligible' (e.g., "New"), they are added back to inventory.
    *   **Loyalty Adjustment**: Deducts points earned from the original purchase.

### `Maintenance Procedures`
*   **`CheckInventoryHealth`**: Analyzes stock levels to identify "Critical Stock" (below safety margin) and "Slow Moving" items (no sales in 90 days).
*   **`CheckDataIntegrity`**: Scans for orphaned records (e.g., order items without headers) or invalid emails.
*   **`CheckSystemHealth`**: Reports database size, table fragmentation, and unresolved error counts.

---

## Triggers

### `trg_low_stock_alert`
**Event**: `AFTER UPDATE ON inventory`
**Logic**:
*   Monitors `quantity_on_hand` changes.
*   Compares new level against `reorder_point`.
*   If stock falls below thresholds, inserts a record into `low_stock_alerts` with severity (INFO, WARNING, CRITICAL).

### `trg_update_customer_lifetime_value`
**Event**: `AFTER INSERT ON orders`
**Logic**:
*   Recalculates the total spent by the customer across all non-cancelled orders.
*   Updates `customer.total_lifetime_value` and `customer_loyalty.total_spent`.
*   Ensures valid data for customer segmentation logic.

### `trg_audit_customer_changes`
**Event**: `AFTER UPDATE ON customer`
**Logic**:
*   Captures `OLD` and `NEW` values of sensitive fields (Name, Email, Address).
*   Logs the change, User ID, and Timestamp to `data_access_audit` for security compliance.

### `trg_prevent_negative_inventory`
**Event**: `BEFORE UPDATE ON inventory`
**Logic**:
*   **Safety Net**: Checks if the proposed `quantity_on_hand` is less than 0.
*   If true, signals a SQL State error ('45000') and aborts the transaction, preventing data corruption.
