{{ config(materialized='view') }}

SELECT 
    o.order_id,
    o.customer_id,
    o.order_date,
    o.total,
    o.status,
    c.city
FROM {{ ref('orders') }} o
LEFT JOIN {{ ref('customers') }} c ON o.customer_id = c.customer_id
