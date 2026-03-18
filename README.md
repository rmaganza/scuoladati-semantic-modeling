# Corso: Modellazione Semantica con dbt

Repository di accompagnamento per la lezione sulla **modellazione semantica** usando dbt e il database AdventureWorks.

## Autore

**Riccardo Maganza** — Agentic Data Intelligence

## Prerequisiti

- Python 3.10+
- [uv](https://github.com/astral-sh/uv) (gestore pacchetti)

## Setup

### 1. Installa le dipendenze

```bash
# Entra nella directory del progetto
cd adventureworks-dbt-course

# Installa le dipendenze con uv
uv sync
```

### 2. Configura il profilo dbt

Crea il file di configurazione del profilo:

```bash
mkdir -p ~/.dbt
cat > ~/.dbt/profiles.yml << 'EOF'
adventureworks:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: $(pwd)/data/adventureworks.duckdb
      threads: 4
EOF
```

### 3. Inizializza dbt

```bash
dbt init adventureworks
```

Modifica `adventureworks/dbt_project.yml` aggiungendo:

```yaml
profile: adventureworks
```

### 4. Carica i dati e rebuild

```bash
cd adventureworks
dbt seed
dbt run
```

## Struttura del Repository

```
adventureworks-dbt-course/
├── README.md                 # Questo file
├── pyproject.toml            # Dipendenze uv
├── notebooks/
│   └── 01_introduzione.ipynb # Notebook interattivo
├── adventureworks/           # Progetto dbt
│   ├── dbt_project.yml
│   ├── seeds/                # Dati CSV
│   └── models/               # Modelli dbt
└── data/                     # Database DuckDB
```

## Contenuto

### Notebook Interattivo

Il notebook `notebooks/01_introduzione.ipynb` contiene:

1. **Esplorazione dei dati grezzi** — Query dirette sui CSV
2. **Dimostrazione del fanout** — Vediamo cosa succede senza modellazione
3. **Esecuzione dei modelli dbt** — Build e risultati
4. **Confronto before/after** — Query giuste vs sbagliate

### Progetto dbt

Il progetto contiene:

- **Seeds**: 5 file CSV con dati AdventureWorks semplificati
- **Staging models**: 5 viste per pulizia/normalizzazione
- **Mart models**: 3 fact tables per analisi

---

## Spiegazione dei Modelli dbt

Questa sezione spiega **cosa fa ogni modello**, **perché è stato creato così**, e **quale problema della modellazione semantica risolve**.

### Livello 1: Seeds (Dati Grezzi)

I seed sono file CSV caricati direttamente nel database. Rappresentano i **dati sorgente**, senza alcuna trasformazione.

| File | Contenuto | Note |
|------|-----------|------|
| `seeds/customers.csv` | 5 clienti | Include città per segmentazione |
| `seeds/orders.csv` | 10 ordini | Stati: 1=pending, 5=shipped, 6=cancelled |
| `seeds/order_lines.csv` | 13 righe | Include sconti (gross vs net) |
| `seeds/products.csv` | 5 prodotti | Biciclette e accessori |
| `seeds/categories.csv` | 5 categorie | Category + subcategory |

**Perché esistono**: Senza dati, non c'è modello. I seeds simulano un database sorgente.

---

### Livello 2: Staging Models

I modelli staging sono il **primo livello di trasformazione**. Sono viste (`view`) che:

- Puliscono i nomi delle colonne
- Normalizzano i tipi di dati
- Arricchiscono con JOIN semplici

**Regola fondamentale**: Uno staging model legge da **un solo seed** (o da un altro staging). Non fa aggregazioni.

#### `stg_customers.sql`

```sql
{{ config(materialized='view') }}

SELECT 
    customer_id,
    first_name,
    last_name,
    email,
    city
FROM {{ ref('customers') }}
```

**Cosa fa**: Semplice pass-through. Rinomina/seleziona colonne.

**Perché esiste**: 
- Definisce il **contratto** del livello customer
- Se domani cambi il nome della colonna `first_name` nel CSV, modifichi solo questo file
- Tutti i modelli a valle continuano a funzionare

---

#### `stg_orders.sql`

```sql
{{ config(materialized='view') }}

SELECT 
    order_id,
    customer_id,
    order_date,
    total,
    status
FROM {{ ref('orders') }}
```

**Cosa fa**: Pass-through con selezione campi.

**Perché esiste**: 
- Separa il livello dati grezzi da quello business
- Se aggiungi campi al CSV, questo modello li espone o nasconde

---

#### `stg_products.sql`

```sql
{{ config(materialized='view') }}

SELECT 
    product_id,
    name,
    category_id,
    subcategory_id,
    price
FROM {{ ref('products') }}
```

**Cosa fa**: Pass-through con campi prodotto.

**Perché esiste**: Prepara la struttura per arricchimenti futuri.

---

#### `stg_categories.sql`

```sql
{{ config(materialized='view') }}

SELECT 
    category_id,
    subcategory_id,
    name AS category_name,
    subcategory_name
FROM {{ ref('categories') }}
```

**Cosa fa**: Rinomina `name` in `category_name` per chiarezza.

**Perché esiste**: Evita ambiguità quando si fa JOIN con altre tabelle che hanno anche una colonna `name`.

---

#### `stg_order_lines.sql` ⚠️ PIÙ IMPORTANTE

```sql
{{ config(materialized='view') }}

SELECT 
    ol.order_line_id,
    ol.order_id,
    ol.product_id,
    ol.quantity,
    ol.unit_price,
    ol.line_total AS gross_total,      -- ⚠️ Rinominato!
    ol.line_total * 0.9 AS net_total,  -- ⚠️ Calcolato! (10% sconto)
    p.name AS product_name,
    p.category_id,
    p.subcategory_id,
    pc.category_name,
    pc.subcategory_name
FROM {{ ref('order_lines') }} ol
LEFT JOIN {{ ref('stg_products') }} p ON ol.product_id = p.product_id
LEFT JOIN {{ ref('stg_categories') }} pc ON p.subcategory_id = pc.subcategory_id
```

**Cosa fa**: 
- JOIN con products e categories per arricchimento
- Calcola `net_total` = `gross_total * 0.9` (simula uno sconto del 10%)

**Perché è importante**: 
- Qui vediamo il **pattern fondamentale** dello staging: arricchimento con JOIN
- Il calcolo di `net_total` dimostra come si aggiunge **business logic** al livello più basso
- Questo campo sarà usato dai mart per metriche accurate

---

### Livello 3: Mart Models (Fact Tables)

I modelli mart sono il cuore della **modellazione semantica**. Sono tabelle (`table`) pre-calcolate che contengono le metriche di business.

**Regola fondamentale**: Un mart fa sempre aggregazioni (GROUP BY).

#### `fct_orders.sql` — Analisi a Livello Ordine

```sql
{{ config(materialized='table') }}

SELECT 
    o.order_id,
    o.order_date,
    o.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    c.city AS customer_city,
    o.total AS order_header_total,    -- ⚠️ Campo grezzo
    COUNT(ol.order_line_id) AS line_count,
    SUM(ol.quantity) AS total_items,
    SUM(ol.gross_total) AS gross_revenue,  -- ⚠️ Da order_lines!
    SUM(ol.net_total) AS net_revenue        -- ⚠️ Con sconto!
FROM {{ ref('stg_orders') }} o
LEFT JOIN {{ ref('stg_order_lines') }} ol ON o.order_id = ol.order_id
LEFT JOIN {{ ref('stg_customers') }} c ON o.customer_id = c.customer_id
GROUP BY o.order_id, o.order_date, o.customer_id, 
         c.first_name, c.last_name, c.city, o.total
```

**Cosa calcola**:
- `gross_revenue`: somma dei totali lordi delle righe
- `net_revenue`: somma dei totali netti (con sconto)
- `line_count`: numero di righe per ordine

**Perché `order_header_total` E `gross_revenue`?**

| Campo | Sorgente | Uso |
|-------|----------|-----|
| `order_header_total` | `orders.total` | Per confronto/reconciliazione |
| `gross_revenue` | `SUM(order_lines.line_total)` | Per analisi accurate |

**Problema che risolve**: Il campo `orders.total` può essere obsoleto o impreciso. Calcolando da `order_lines` otteniamo un valore **riconciliabile** — la somma delle righe deve uguagliare il totale (a meno di arrotondamenti).

---

#### `fct_products.sql` — Analisi a Livello Prodotto

```sql
{{ config(materialized='table') }}

SELECT 
    p.product_id,
    p.name AS product_name,
    p.category_id,
    p.subcategory_id,
    pc.category_name,
    pc.subcategory_name,
    COUNT(DISTINCT ol.order_id) AS orders_with_product,  -- ⚠️ DISTINCT!
    COALESCE(SUM(ol.quantity), 0) AS units_sold,
    COALESCE(SUM(ol.gross_total), 0) AS gross_revenue,
    COALESCE(SUM(ol.net_total), 0) AS net_revenue
FROM {{ ref('stg_products') }} p
LEFT JOIN {{ ref('stg_order_lines') }} ol ON p.product_id = ol.product_id
LEFT JOIN {{ ref('stg_categories') }} pc ON p.subcategory_id = pc.subcategory_id
GROUP BY p.product_id, p.name, p.category_id, p.subcategory_id,
         pc.category_name, pc.subcategory_name
```

**Cosa calcola**:
- `orders_with_product`: quanti ordini contengono questo prodotto
- `units_sold`: somma delle quantità
- `gross_revenue` / `net_revenue`: revenue con/senza sconto

**Il problema del FANOUT spiegato** (il concetto più importante!):

```
Senza DISTINCT:  Ordine 1 ha 3 prodotti diversi → conta 3 ordini ❌
Con DISTINCT:     Ordine 1 ha 3 prodotti diversi → conta 1 ordine ✅
```

Se un cliente compra 3 prodotti in un ordine, e noi facciamo:
```sql
SELECT product_id, COUNT(order_id) FROM order_lines GROUP BY product_id
```

Il risultato sarà **sballato** — ogni ordine viene contato più volte.

**Soluzione nel modello**: `COUNT(DISTINCT order_id)` — il modello fa questo calcolo **una volta**, e tutti lo usano correttamente.

---

#### `fct_customers.sql` — Analisi a Livello Cliente

```sql
{{ config(materialized='table') }}

SELECT 
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email,
    c.city,
    COUNT(DISTINCT o.order_id) AS order_count,           -- ⚠️ DISTINCT!
    COALESCE(SUM(o.total), 0) AS lifetime_gross_value,   -- Da header
    COALESCE(SUM(ol.net_total), 0) AS lifetime_net_value -- Da righe
FROM {{ ref('stg_customers') }} c
LEFT JOIN {{ ref('stg_orders') }} o ON c.customer_id = o.customer_id
LEFT JOIN {{ ref('stg_order_lines') }} ol ON o.order_id = ol.order_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.city
```

**Cosa calcola**:
- `order_count`: numero di ordini unici per cliente
- `lifetime_gross_value`: somma dei totali header
- `lifetime_net_value`: somma dei totali netti (più accurato)

**Perché due lifetime value?**

| Metrica | Calcolo | Affidabilità |
|---------|---------|--------------|
| `lifetime_gross_value` | `SUM(orders.total)` | Bassa — campo denormalizzato |
| `lifetime_net_value` | `SUM(order_lines.net_total)` | Alta — calcolato |

Il modello espone entrambi per permettere **reconciliazione**: gross - net dovrebbe uguagliare il totale sconti.

---

## Prima vs Dopo: Riepilogo

| Aspetto | Prima (SQL Diretto) | Dopo (Modello Semantico) |
|---------|---------------------|-------------------------|
| **Query** | Complessa, ripetuta | `SELECT * FROM fct_xxx` |
| **Logica** | Duplicata in ogni query | Centralizzata nel modello |
| **Errori** | Fanout, DISTINCT dimenticati | Corretto by design |
| **Manutenzione** | Difficile | Cambi in un punto |
| **Testing** | Difficile | Test sul modello |

---

## Esercizi Proposti

1. **Aggiungi un nuovo campo**: Aggiungi `discount_pct` ai seed e calcola `net_total` correttamente
2. **Nuovo mart**: Crea `fct_daily_sales` con revenue per giorno
3. **Filtri**: Aggiungi solo ordini shipped ai mart (status = 5)

## Guida Rapida

### Eseguire il notebook

```bash
uv run jupyter lab notebooks/01_introduzione.ipynb
```

### Comandi dbt

| Comando | Descrizione |
|---------|-------------|
| `dbt seed` | Carica i CSV nel database |
| `dbt run` | Esegue tutti i modelli |
| `dbt run -m <modello>` | Esegue un modello specifico |
| `dbt test` | Esegue i test |
| `dbt docs generate` | Genera documentazione |
| `dbt docs serve` | Avvia server docs local |

## Documentazione dbt

La documentazione dbt è già generata e disponibile nella cartella `docs/`. Puoi visualizzarla in due modi:

### Opzione 1: Server locale (consigliata, interattiva)

```bash
cd adventureworks
dbt docs serve
```

Questo avvia un server locale su http://localhost:8080 con la documentazione interattiva.

### Opzione 2: Statico (senza server)

Apri direttamente `docs/index.html` nel browser. Nota: alcune funzionalità richiedono un server locale.

## Dati

I dati rappresentano uno schema AdventureWorks semplificato:

- **5 clienti** (con città)
- **10 ordini** (vari stati: pending, shipped, cancelled)
- **13 righe ordine** (con sconti!)
- **5 prodotti** (biciclette e accessori)
- **5 categorie/sottocategorie**

### Schema

```
customers ────── orders ────── order_lines ────── products
   │              │               │                  │
   └──────────────┴───────────────┴──────────────────┘
                                        │
                                     categories
```

## Errori Comuni e Come Evitarli

### 1. Fanout (Raddoppio)

**Problema**: JOIN senza aggregazione corretta raddoppia i conteggi.

**Soluzione**: Usa `COUNT(DISTINCT ...)` o aggrega prima di joinare.

### 2. Campi Non Allineati

**Problema**: Usare `orders.total` invece di calcolare da `order_lines`.

**Soluzione**: La modellazione semantica calcola sempre dai dettagli.

### 3. Filtri Mancanti

**Problema**: Includere ordini cancellati o pending.

**Soluzione**: Filtra sempre per `status = 'shipped'`.

## Risorse

- [dbt Docs](https://docs.getdbt.com/)
- [dbt DuckDB Adapter](https://github.com/duckdb/dbt-duckdb)
- [AdventureWorks Schema](https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure)

## Licenza

MIT License
