CREATE OR REPLACE VIEW v_Product_Enriched AS
SELECT
    p.product_id,
    p.product_name,
    c.category_name,
    s.company_name AS supplier,
    p.unit_price
FROM products p
LEFT JOIN categories c ON p.category_id = c.category_id
LEFT JOIN suppliers s ON p.supplier_id = s.supplier_id;

CREATE OR REPLACE VIEW v_Order_Sales AS
SELECT
    o.order_id,
    od.product_id,
    o.customer_id,
    o.employee_id,
    o.ship_via,
    o.order_date,
    o.required_date,
    o.shipped_date,
    od.unit_price,
    od.quantity,
    od.discount,
    od.unit_price * od.quantity * (1 - od.discount) AS total_line_amount
FROM orders o
INNER JOIN order_details od ON o.order_id = od.order_id;

CREATE OR REPLACE VIEW v_Customer_Geo AS
SELECT DISTINCT
    c.customer_id,
    c.company_name,
    c.city,
    c.country
FROM customers c
INNER JOIN orders o ON c.customer_id = o.customer_id;