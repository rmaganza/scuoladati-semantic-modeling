# Scuola Dati — Modellazione Semantica con dbt

**Autore**: Riccardo Maganza — Agentic Data Intelligence

Corso in due lezioni su semantic layer, orchestrazione e agenti AI applicati ai dati.

---

## Lezioni

### [Lezione 1 — Il Semantic Layer](lezione1/README.md)

Costruisce il contratto sui dati con dbt e AdventureWorks.

- Modelli staging e fact table (`fct_orders`, `fct_customers`, `fct_products`)
- Il problema del fanout e come risolverlo
- Semantic layer dichiarativo con MetricFlow (`_semantic_layer.yml`)
- Test di qualità dati (`dbt test`)

**Notebook**: `lezione1/01_introduzione.ipynb`

```bash
uv run jupyter lab lezione1/01_introduzione.ipynb
```

---

### [Lezione 2 — Il Full Stack Agentico](lezione2/README.md)

Aggiunge orchestrazione e intelligenza sopra il semantic layer.

- **Layer 2**: Dagster orchestra dbt, schedule e sensor (`lezione2/dagster_pipeline.py`)
- **Layer 3**: Agente Pydantic AI con tool calling, context injection e agent loop
- Monitoring automatico con alert strutturati (`MonitoringAlert`)

**Notebook**: `lezione2/02_agente_semantico.ipynb`

```bash
uv run jupyter lab lezione2/02_agente_semantico.ipynb
```

---

## Setup

```bash
# Installa le dipendenze
uv sync

# Carica i dati e costruisci i modelli (dalla cartella adventureworks/)
cd adventureworks && uv run dbt seed && uv run dbt run && cd ..

# Crea il file .env per la Lezione 2
echo "ANTHROPIC_API_KEY=sk-ant-..." > .env
```

Per Dagster (Lezione 2):

```bash
uv sync --extra dagster
```

## Struttura

```
scuoladati-semantic-modeling/
├── README.md                     # Questo file
├── pyproject.toml                # Dipendenze uv
├── profiles.yml                  # Profilo dbt
├── lezione1/
│   ├── README.md                 # Guida lezione 1
│   └── 01_introduzione.ipynb
├── lezione2/
│   ├── README.md                 # Guida lezione 2
│   ├── dagster_pipeline.py
│   └── 02_agente_semantico.ipynb
└── adventureworks/               # Progetto dbt (condiviso tra le lezioni)
    ├── dbt_project.yml
    ├── seeds/                    # CSV sorgente
    ├── models/                   # Staging, marts, semantic layer
    └── data/                     # Database DuckDB (generato da dbt)
```
