{{ config(materialized='table') }}

-- Time spine richiesto da MetricFlow per dimensioni temporali e join su metric_time
select cast(d as date) as date_day
from generate_series(
    date '2020-01-01',
    date '2035-12-31',
    interval 1 day
) as s(d)
