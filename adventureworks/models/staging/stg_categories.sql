{{ config(materialized='view') }}

SELECT 
    subcategory_id,
    category_id,
    subcategory_name,
    name AS category_name
FROM {{ ref('categories') }}
