# Lezione 2: Il Full Stack Agentico

**Scuola Dati — dbt + Orchestrazione + Agenti AI**

La prima lezione ha costruito il **semantic layer** come contratto formale sui dati.  
Questa lezione aggiunge i due layer mancanti: l'**orchestratore** (Dagster) e l'**agente** (Pydantic AI).

---

## Cosa Facciamo

Costruiamo un sistema di **monitoring automatico** che:

1. Materializza le fact table via Dagster (`dagster asset materialize`)
2. Un agente AI controlla tre metriche definite nel semantic layer
3. L'agente produce alert strutturati con severità, SQL usato e azione consigliata

Le tre metriche monitorate sono tutte definite in `_semantic_layer.yml`:
`total_net_revenue`, `order_count`, `avg_net_revenue_per_order`.

---

## Installazione

### 1. Dipendenze base

```bash
uv sync
```

Installa: dbt-duckdb, pydantic-ai, anthropic, python-dotenv, sentence-transformers, numpy, jupyter e tutte le dipendenze transitive.

### 2. API Key Anthropic

Crea un file `.env` nella root del progetto (già in `.gitignore`):

```
ANTHROPIC_API_KEY=sk-ant-...
```

Il notebook lo carica automaticamente con `load_dotenv` alla prima cella.

### 3. Dagster (opzionale)

Richiesto solo per le celle Dagster (celle 6–7 del notebook):

```bash
uv sync --extra dagster
```

### 4. Verifica

```bash
# Verifica dbt e database (dalla cartella adventureworks/)
uv run dbt compile --profiles-dir ..

# Verifica agente (dalla root)
uv run python -c "from pydantic_ai import Agent; print('ok')"

# Verifica Dagster (opzionale)
uv run python -c "import dagster; print(dagster.__version__)"
```

---

## Architettura: I Tre Layer

```
  SORGENTI DATI
       │
       ▼
  ┌────────────────────────────────────────────────────────────┐
  │  LAYER 1 — CONTRATTO DEI DATI  (dbt)                      │
  │                                                            │
  │  seeds CSV ──► staging views ──► fact tables              │
  │                                       │                   │
  │                          _semantic_layer.yml              │
  │                     (metriche, misure, dimensioni)        │
  └────────────────────────────────────────────────────────────┘
                                          │ asset pronti
                                          ▼
  ┌────────────────────────────────────────────────────────────┐
  │  LAYER 2 — ORCHESTRAZIONE  (Dagster)                      │
  │                                                            │
  │  Schedule ──► dbt run ──► dbt test ──► SUCCESS            │
  │                                              │            │
  │                                         Sensor           │
  │                                     (rileva l'evento)    │
  └────────────────────────────────────────────────────────────┘
                                                 │ trigger
                                                 ▼
  ┌────────────────────────────────────────────────────────────┐
  │  LAYER 3 — INTELLIGENZA  (Pydantic AI + Claude)           │
  │                                                            │
  │  @system_prompt: corpus dbt  ← context injection         │
  │  Tool 1: execute_query()     ← SQL su DuckDB             │
  │  Tool 2: read_alert_thresholds() ← config soglie         │
  │                                                            │
  │  Loop: controlla metrica ──► anomalia? ──► alert          │
  └────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
                       OUTPUT STRUTTURATO
                         MonitoringAlert
```

**Separazione delle responsabilità**: nessun layer fa il lavoro dell'altro.  
dbt non orchestra. Dagster non ragiona. L'agente non trasforma dati.

---

## Componenti e a Cosa Servono

### dbt (Layer 1)

Fornisce due cose all'agente:

1. **Il database fisico** (`adventureworks.duckdb`) con le fact table calcolate e testate
2. **Il corpus testuale** — tutti i file YAML e SQL — che l'agente riceve nel system prompt per trovare le formule delle metriche

L'agente non ha le formule hard-coded: le legge dal corpus, come farebbe un analista che entra in un progetto per la prima volta.

### Dagster (Layer 2)

Orchestra il pipeline e triggera l'agente al momento giusto.

Senza Dagster, qualcuno dovrebbe ricordarsi di eseguire dbt ogni giorno e poi lanciare l'agente a mano. Con Dagster il sistema è autonomo: lo schedule esegue dbt, il sensor rileva il completamento, l'agente parte automaticamente.

Il file `dagster_pipeline.py` nella root è un pipeline Dagster completo ed eseguibile.

### Pydantic AI (Layer 3)

Framework che collega un LLM (Claude) a funzioni Python tipizzate.

- L'LLM decide quali tool chiamare e in quale ordine
- I tool sono funzioni Python normali con type hint
- L'output finale è un oggetto Pydantic validato (`MonitoringAlert`), non testo libero

### Claude (Anthropic)

Modello linguistico che ragiona, decide quali tool chiamare, interpreta i risultati SQL e produce il `MonitoringAlert` finale. Configurabile via variabile d'ambiente:

```bash
PYDANTIC_AI_MODEL=anthropic:claude-sonnet-4-6
```

### DuckDB

Database su file con le fact table. L'agente lo interroga in sola lettura (`read_only=True`).

---

## File di Questa Lezione

```
scuoladati-semantic-modeling/
├── README.md                     # Indice del corso (root)
├── .env                          # API key (non versionato)
└── lezione2/
    ├── README.md                 # Questo file
    ├── dagster_pipeline.py       # Pipeline Dagster (eseguibile)
    └── 02_agente_semantico.ipynb # Notebook della lezione
```

### `dagster_pipeline.py`

Contiene:
- `adventureworks_assets` — tutti i modelli dbt come asset Dagster
- `dbt_refresh_job` — job che materializza i tre fact table
- `daily_schedule` — esecuzione giornaliera alle 06:00
- `post_run_agent_sensor` — sensor che triggera l'agente dopo ogni run completato

---

## Definizioni da Capire

### Agent (Pydantic AI)

Un agente è un LLM con tool e un output atteso. Gestisce autonomamente il ciclo
*ragiona → chiama tool → osserva → ragiona di nuovo* finché non produce l'output richiesto.

```python
monitoring_agent = Agent(
    "anthropic:claude-sonnet-4-6",
    deps_type=AgentStack,        # risorse iniettate a runtime
    output_type=MonitoringAlert, # Pydantic model dell'output
)
```

### `deps` — Dependency Injection

I tool hanno bisogno di risorse (database, corpus) che non possono ricevere come
argomenti normali — quelli li decide l'LLM. La soluzione: si passa un oggetto `deps`
a `.run(deps=...)`, e ogni tool lo riceve via `ctx.deps`.

```python
class AgentStack:
    db_path: str          # path al DuckDB
    corpus_text: str      # corpus dbt per il system prompt

result = await monitoring_agent.run("...", deps=AgentStack(ROOT))

@monitoring_agent.tool
def execute_query(ctx: RunContext[AgentStack], sql: str) -> str:
    con = duckdb.connect(ctx.deps.db_path, read_only=True)
    ...
```

### `output_type` — Output Strutturato

Invece di testo libero, l'agente produce un oggetto Pydantic validato:

```python
class MonitoringAlert(BaseModel):
    metric: str
    current_value: str
    severity: Literal["ok", "warning", "critical"]
    description: str
    recommended_action: str | None
    executed_sql: str
    ...
```

Il chiamante può fare `alert.severity == "critical"` invece di parsare una stringa.

### Tool

Funzione Python decorata con `@agent.tool`. L'LLM vede solo nome, docstring e schema
dei parametri — non il codice — e decide autonomamente quando chiamarla.

```python
@monitoring_agent.tool
def execute_query(ctx: RunContext[AgentStack], sql: str) -> str:
    """
    Esegue una query SQL sul database DuckDB e restituisce il risultato.
    Scrivi query usando la logica trovata nel corpus dbt (formule, filtri).
    """
    ...
```

### Context Injection

Il corpus dbt (YAML + SQL) viene iniettato interamente nel system prompt tramite
`@agent.system_prompt`. Il modello legge formule e definizioni direttamente nel contesto.

Funziona perché il corpus è piccolo (~5K token su 200K disponibili). Per corpus grandi
serve RAG con embeddings — vedi la sezione Appendice nel notebook.

```python
@monitoring_agent.system_prompt
def inject_corpus(ctx: RunContext[AgentStack]) -> str:
    return f"CORPUS DBT:\n\n{ctx.deps.corpus_text}"
```

### Due Loop Sovrapposti

**Loop esterno** (`monitoring_loop`): itera sulle metriche, chiama l'agente una volta per ciascuna.

**Loop interno** (Pydantic AI): per ogni `.run(...)`, l'LLM decide quante volte
invocare i tool e in quale ordine, finché non compila `MonitoringAlert`.

```
for metric in metrics:                       ← loop esterno (nostro)
    monitoring_agent.run(metric, deps=stack)
        LLM → read_alert_thresholds()        ← loop interno (Pydantic AI)
        LLM → execute_query(sql)
        LLM → execute_query(sql2)  # può riprovare
        LLM → MonitoringAlert
```

### Asset (Dagster)

Un artefatto prodotto da un pipeline (es. la tabella `fct_orders`). Con `dagster-dbt`,
ogni modello dbt diventa automaticamente un asset Dagster, e Dagster conosce la lineage.

### Sensor (Dagster)

Osservatore che fa polling su una condizione e, quando la trova vera, emette un
`RunRequest` per avviare un job. `post_run_agent_sensor` legge `run_results.json`
dopo ogni dbt run e triggera l'agente se trova un run più recente dell'ultimo processato.

---

## I Tre Pattern dell'Agente

### Pattern 1 — Tool Calling su Dati Strutturati
L'agente chiama funzioni Python per interrogare il database.
Il modello scrive la query SQL, il tool la esegue e restituisce il risultato.

### Pattern 2 — Context Injection
Il corpus dbt viene iniettato interamente nel system prompt.
Il modello legge formule e definizioni direttamente nel contesto, senza tool di ricerca.

### Pattern 3 — Agent Loop
L'agente gira in loop su una lista di metriche, producendo un `MonitoringAlert` per ciascuna.
Ogni iterazione è indipendente → scalabile in parallelo con `asyncio.gather()`.

I tre pattern si combinano: il loop (3) chiama l'agente → il corpus nel contesto (2)
fornisce le formule → il tool calling (1) calcola i valori → produce l'alert strutturato.

---

## Come Eseguire

### Solo l'agente (senza Dagster)

```bash
uv run jupyter lab lezione2/02_agente_semantico.ipynb
```

Esegui le celle in ordine. Le celle Dagster (6–7) richiedono `uv sync --extra dagster`;
le celle dell'agente (dalla 10 in poi) richiedono solo la API key nel `.env`.

### Materializzare gli asset con Dagster (senza web server)

```bash
# Genera il manifest (dalla cartella adventureworks/)
dbt compile --profiles-dir ..

# Materializza i tre fact table (dalla root)
dagster asset materialize -f lezione2/dagster_pipeline.py --select fct_customers,fct_orders,fct_products
```

### Interfaccia web Dagster

```bash
dagster dev -f lezione2/dagster_pipeline.py
```

Poi apri http://localhost:3000 per il lineage graph, i log dei run e lo schedule.

---

## Output Atteso

Con i dati AdventureWorks inclusi nel progetto:

| Metrica | Valore atteso | Soglia warning | Esito |
|---|---|---|---|
| `total_net_revenue` | ~€9.740 | €12.000 | ⚠️ warning |
| `order_count` | 6 ordini | 5 ordini | ✅ ok |
| `avg_net_revenue_per_order` | ~€1.623 | €1.500 | ✅ ok |

L'ordine 9 è in stato 3 (in lavorazione) invece di 5 (spedito): i suoi €4.200 di ricavo
non vengono conteggiati, portando `total_net_revenue` sotto la soglia di warning.

---

## Notebook vs Produzione

| Aspetto | Notebook | Produzione |
|---|---|---|
| **Trigger** | Chiamata diretta | Dagster sensor |
| **Database** | DuckDB locale | Snowflake / BigQuery |
| **Corpus** | File su disco | dbt Cloud API / metadata store |
| **Alert** | `print()` | Slack / PagerDuty |
| **Parallelismo** | Loop sequenziale | `asyncio.gather()` per N agenti |
| **Stato** | In memoria | Tabella `monitoring_alerts` nel DB |

---

## Risorse

- [Pydantic AI — Documentazione](https://ai.pydantic.dev/)
- [Pydantic AI — Dependency Injection](https://ai.pydantic.dev/dependencies/)
- [Pydantic AI — System Prompts](https://ai.pydantic.dev/agents/#system-prompts)
- [Dagster — Getting Started](https://docs.dagster.io/getting-started)
- [dagster-dbt — Integrazione dbt](https://docs.dagster.io/integrations/dbt)
- [Anthropic API](https://docs.anthropic.com/)
