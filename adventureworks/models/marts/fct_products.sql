{{ config(materialized='table') }}

SELECT 
    p.product_id,
    p.name AS product_name,
    p.category_id,
    p.subcategory_id,
    pc.category_name AS category_name,
    pc.subcategory_name,
    COUNT(DISTINCT ol.order_id) AS orders_with_product,
    COALESCE(SUM(ol.quantity), 0) AS units_sold,
    COALESCE(SUM(ol.line_total), 0) AS gross_revenue,
    COALESCE(SUM(ol.net_revenue), 0) AS net_revenue
FROM {{ ref('stg_products') }} p
LEFT JOIN {{ ref('stg_order_lines') }} ol ON p.product_id = ol.product_id
LEFT JOIN {{ ref('stg_categories') }} pc ON p.subcategory_id = pc.subcategory_id
GROUP BY p.product_id, p.name, p.category_id, p.subcategory_id, pc.category_name, pc.subcategory_name
