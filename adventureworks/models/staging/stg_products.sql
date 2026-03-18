{{ config(materialized='view') }}

SELECT 
    product_id,
    name,
    category_id,
    subcategory_id,
    price
FROM {{ ref('products') }}
