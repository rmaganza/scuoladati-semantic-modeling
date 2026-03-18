{{ config(materialized='table') }}

SELECT 
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email,
    c.city,
    COUNT(DISTINCT o.order_id) AS order_count,
    COALESCE(SUM(o.total), 0) AS lifetime_value,
    COALESCE(SUM(ol.net_revenue), 0) AS lifetime_net_revenue
FROM {{ ref('stg_customers') }} c
LEFT JOIN {{ ref('stg_orders') }} o ON c.customer_id = o.customer_id AND o.status = 5
LEFT JOIN {{ ref('stg_order_lines') }} ol ON o.order_id = ol.order_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.city
