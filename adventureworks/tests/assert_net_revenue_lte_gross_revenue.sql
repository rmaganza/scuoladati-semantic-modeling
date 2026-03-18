-- Esempio di test singolare: net_revenue non può superare gross_revenue
-- (gli sconti riducono il revenue, non lo aumentano)
-- Il test passa se la query restituisce 0 righe
SELECT order_id, gross_revenue, net_revenue
FROM {{ ref('fct_orders') }}
WHERE net_revenue > gross_revenue
