{{ config(materialized='view') }}

SELECT 
    ol.order_line_id,
    ol.order_id,
    ol.product_id,
    ol.quantity,
    ol.unit_price,
    ol.line_total,
    ol.discount_pct,
    -- Calcolo revenue NETTO (dopo sconto)
    ol.line_total * (1 - ol.discount_pct) AS net_revenue,
    p.name AS product_name,
    p.category_id,
    p.subcategory_id,
    pc.name AS category_name,
    pc.subcategory_name
FROM {{ ref('order_lines') }} ol
LEFT JOIN {{ ref('products') }} p ON ol.product_id = p.product_id
LEFT JOIN {{ ref('categories') }} pc ON p.subcategory_id = pc.subcategory_id
