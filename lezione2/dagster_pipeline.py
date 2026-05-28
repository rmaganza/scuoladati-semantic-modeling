"""
dagster_pipeline.py — Full Stack Agentico con dbt + Dagster

Per eseguire (interfaccia web):
    uv sync --extra dagster
    dagster dev -f lezione2/dagster_pipeline.py
    # poi apri http://localhost:3000

Per materializzare gli asset una volta sola (senza web server):
    dagster asset materialize -f lezione2/dagster_pipeline.py --select fct_customers,fct_orders,fct_products
"""

from pathlib import Path

from dagster import (
    AssetExecutionContext,
    Definitions,
    RunRequest,
    ScheduleDefinition,
    SensorEvaluationContext,
    SkipReason,
    define_asset_job,
    sensor,
)
from dagster_dbt import DbtCliResource, DbtProject, dbt_assets

import json

# ── Progetto dbt ──────────────────────────────────────────────────────────────
DBT_PROJECT = DbtProject(
    project_dir=Path(__file__).parent.parent / "adventureworks",
    profiles_dir=Path(__file__).parent.parent,
)


@dbt_assets(manifest=DBT_PROJECT.manifest_path)
def adventureworks_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    """Tutti i modelli dbt come asset Dagster (lineage automatica)."""
    yield from dbt.cli(["run"], context=context).stream()


# ── Job: materializza i fact tables ──────────────────────────────────────────
dbt_job = define_asset_job(
    "dbt_refresh_job",
    selection=["fct_customers", "fct_orders", "fct_products"],
)

# ── Schedule: ogni giorno alle 06:00 ─────────────────────────────────────────
daily_schedule = ScheduleDefinition(
    job=dbt_job,
    cron_schedule="0 6 * * *",
    name="daily_dbt_refresh",
)


# ── Sensor: triggera l'agente dopo ogni run completato ───────────────────────
@sensor(job=dbt_job)
def post_run_agent_sensor(context: SensorEvaluationContext):
    """
    Rileva il completamento di un run dbt e lancia il job dell'agente.

    In produzione questo sensor interroga il Dagster event log per trovare
    nuovi run completati con successo. Qui usiamo una logica semplificata
    basata su un cursor (ultimo run_id processato).

    Per collegare l'agente Python: chiama l'API REST del monitoring agent
    (FastAPI + Pydantic AI) con una richiesta POST.
    """

    last_cursor = context.cursor or "0"

    # In produzione: query a context.instance.get_run_records(...)
    # Qui: legge un file di stato creato da dbt dopo ogni run
    run_results_path = (
        Path(__file__).parent.parent / "adventureworks" / "target" / "run_results.json"
    )
    if not run_results_path.exists():
        return SkipReason("run_results.json non trovato (eseguire prima dbt run).")

    run_data = json.loads(run_results_path.read_text())
    generated_at = run_data.get("metadata", {}).get("generated_at", "")

    if generated_at == last_cursor:
        return SkipReason("Nessun nuovo run dbt da processare.")

    context.update_cursor(generated_at)
    context.log.info(f"Nuovo run dbt rilevato: {generated_at}")

    # Esempio: chiama il monitoring agent via HTTP
    # try:
    #     payload = json.dumps({"metriche": ["total_net_revenue",
    #                                         "clienti_senza_ordini_pct",
    #                                         "avg_net_revenue_per_order"]}).encode()
    #     req = urllib.request.Request(
    #         "http://localhost:8000/monitoring/run",
    #         data=payload,
    #         headers={"Content-Type": "application/json"},
    #         method="POST",
    #     )
    #     with urllib.request.urlopen(req, timeout=120) as resp:
    #         context.log.info(f"Agent response: {resp.read().decode()}")
    # except Exception as e:
    #     context.log.warning(f"Agent call fallita: {e}")

    return RunRequest(
        run_key=generated_at,
        tags={"source": "post_dbt_sensor"},
    )


# ── Registry Dagster ──────────────────────────────────────────────────────────
defs = Definitions(
    assets=[adventureworks_assets],
    jobs=[dbt_job],
    schedules=[daily_schedule],
    sensors=[post_run_agent_sensor],
    resources={
        "dbt": DbtCliResource(project_dir=DBT_PROJECT),
    },
)
