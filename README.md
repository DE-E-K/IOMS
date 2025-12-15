# IOMS - Inventory and Order Management System

This project provides a robust database schema for an Inventory and Order Management System (IOMS) tailored for e-commerce applications. The core of this project is the Entity-Relationship Diagram (ERD) and the corresponding SQL implementation to manage products, inventory, and customer orders efficiently.

## Key Features

- **Order Management**: Tracks customer orders from placement to fulfillment.
- **Inventory Control**: Manages product stock levels.
- **Stock Sufficiency Checks**: Ensures that there is enough stock to fulfill a new order before it is confirmed.
- **Low Stock Alerts**: Provides a mechanism to alert managers when inventory for a product falls below a certain threshold.
- **Scalable Schema**: A well-designed database schema that can grow with the business.

## Database Schema

The database is designed to handle the complexities of an e-commerce business. The main entities include:

- **`Products`**: Stores information about each product, such as name, description, and price.
- **`Customers`**: Contains customer details.
- **`Orders`**: Holds information about each order, including the customer who placed it, the order date, and its status.
- **`Order_Item`**: A junction table that links products to orders, specifying the quantity of each product in an order.
- **`Inventory`**: Tracks the quantity on hand for each product and sets a reorder level for low-stock alerts.

### Entity-Relationship Diagram (ERD)

The schema is built around the relationships between these core tables:

- A `Customer` can have multiple `Orders`.
- An `Order` consists of multiple `Order_Items`.
- Each `Order_Item` corresponds to a single `Product`.
- The `Inventory` table has a one-to-one relationship with the `Product` table.

## Technologies Used

- **MySQL**: The primary language used for defining and manipulating the database.

## Getting Started

To get this system up and running, you will need a SQL database server (like MySQL).

1.  **Create the Database**: by excute the Schema Script `ioms_ddl.sql` file (not included in this README) to create the tables and relationships. which is also contain the populated initial sample data for database to use.

## Usage Examples

Here are some example SQL queries to demonstrate how to interact with the system in the `ioms_dml.sql` file.

### ERD
Understand the ERD by having a look on the `IOMS_ERD.pdf` file