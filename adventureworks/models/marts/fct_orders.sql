{{ config(materialized='table') }}

SELECT 
    o.order_id,
    o.order_date,
    o.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    c.city,
    o.status,
    o.total AS order_total,
    COUNT(ol.order_line_id) AS line_count,
    SUM(ol.quantity) AS total_items,
    COALESCE(SUM(ol.line_total), 0) AS gross_revenue,
    COALESCE(SUM(ol.net_revenue), 0) AS net_revenue
FROM {{ ref('stg_orders') }} o
LEFT JOIN {{ ref('stg_order_lines') }} ol ON o.order_id = ol.order_id
LEFT JOIN {{ ref('stg_customers') }} c ON o.customer_id = c.customer_id
WHERE o.status = 5  -- Solo ordini spediti
GROUP BY o.order_id, o.order_date, o.customer_id, c.first_name, c.last_name, c.city, o.status, o.total
