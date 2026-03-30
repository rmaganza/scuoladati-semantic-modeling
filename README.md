# Corso: Modellazione Semantica con dbt

Repository di accompagnamento per la lezione sulla **modellazione semantica** usando dbt e il database AdventureWorks.

## Autore

**Riccardo Maganza** — Agentic Data Intelligence

## Prerequisiti

- **Python 3.10–3.13** (dbt non supporta ancora Python 3.14)
- **uv** — gestore pacchetti Python ([installazione](https://docs.astral.sh/uv/getting-started/installation/))

**Nota**: Non serve installare dbt separatamente. È incluso nelle dipendenze del progetto (`dbt-duckdb` → `dbt-core`). Dopo `uv sync` puoi usare `uv run dbt` (o `dbt` se attivi l’ambiente virtuale).

Per installare uv (se non presente):

```bash
# macOS/Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# oppure con pip
pip install uv
```

## Setup da zero

Segui questi passaggi in ordine per configurare il progetto da zero.

### 1. Clona il repository

```bash
git clone <url-del-repository>
cd scuoladati-semantic-modeling   # oppure il nome della cartella creata
```

_(Sostituisci `<url-del-repository>` con l’URL effettivo del repo. Se hai scaricato lo ZIP, decomprimi e entra nella cartella.)_

### 2. Installa le dipendenze

```bash
uv sync
```

Questo crea un ambiente virtuale e installa DuckDB, dbt-duckdb, **dbt-metricflow** (MetricFlow + dipendenze del semantic layer), Jupyter e le altre dipendenze.

### 3. Configura dbt e crea il database

**Opzione A — Profilo globale (consigliata)**

```bash
cd adventureworks
mkdir -p data
mkdir -p ~/.dbt
cat > ~/.dbt/profiles.yml << EOF
adventureworks:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: $(pwd)/data/adventureworks.duckdb
      threads: 4
EOF
```

_(Su Windows, il comando `cat` potrebbe non funzionare. Crea manualmente `%USERPROFILE%\.dbt\profiles.yml` con il contenuto sopra, sostituendo `$(pwd)` con il path assoluto della cartella `adventureworks`, es. `C:\path\to\progetto\adventureworks`.)_

**Opzione B — Profilo nel progetto**

Il repository include un `profiles.yml` nella root. Dalla cartella `adventureworks/`:

```bash
cd adventureworks
mkdir -p data
```

Poi usa `DBT_PROFILES_DIR=..` quando lanci dbt (vedi step 4).

### 4. Carica i dati e costruisci i modelli

Dalla cartella `adventureworks/`:

```bash
# Con profilo globale (Opzione A)
dbt seed
dbt run
dbt test
```

Se usi l’Opzione B:

```bash
DBT_PROFILES_DIR=.. dbt seed
DBT_PROFILES_DIR=.. dbt run
DBT_PROFILES_DIR=.. dbt test
```

### 5. Verifica che tutto funzioni

```bash
# Torna alla root del progetto
cd ..

# Avvia il notebook
uv run jupyter lab notebooks/01_introduzione.ipynb
```

Esegui le celle del notebook: dovresti vedere le tabelle e i risultati delle query. Se il notebook non trova il database, controlla di aver eseguito `dbt seed` e `dbt run` dallo step 4.

## Struttura del Repository

```
scuoladati-semantic-modeling/
├── README.md                 # Questo file
├── pyproject.toml            # Dipendenze uv
├── profiles.yml              # Profilo dbt (opzionale, alternativa a ~/.dbt/)
├── notebooks/
│   └── 01_introduzione.ipynb # Notebook interattivo
├── adventureworks/           # Progetto dbt
│   ├── dbt_project.yml
│   ├── data/                 # Database DuckDB (creato da dbt)
│   ├── seeds/                # Dati CSV
│   └── models/               # Modelli dbt (staging, marts, semantic layer YAML)
└── docs/                     # Documentazione dbt generata
```

**Nota**: Il database DuckDB viene creato in `adventureworks/data/adventureworks.duckdb` quando esegui `dbt seed` o `dbt run`. Il notebook si connette a questo path quando viene eseguito dalla root del progetto.

## Contenuto

### Notebook Interattivo

Il notebook `notebooks/01_introduzione.ipynb` contiene:

1. **Esplorazione dei dati grezzi** — Query dirette sulle tabelle caricate da dbt
2. **Dimostrazione del fanout** — Cosa succede senza modellazione corretta
3. **I modelli dbt in azione** — Build e risultati delle fact table
4. **Confronto before/after** — Query sbagliate vs corrette
5. **Layer semantico e MetricFlow** — Glossario sintetico, perché MetricFlow oltre al SQL sulle fact (tabella nel README), semantic model su `fct_orders`, comandi `mf query` / `mf validate-configs`; dettaglio in *Livello 4*

### Progetto dbt

Il progetto contiene:

- **Seeds**: 5 file CSV con dati AdventureWorks semplificati
- **Staging models**: 5 viste per pulizia e normalizzazione
- **Mart models**: 3 fact table per analisi
- **Semantic layer** (`models/marts/_semantic_layer.yml`): semantic model `orders_semantic` e metriche (`total_net_revenue`, …) per MetricFlow
- **Time spine** (`time_spine_daily` + `_time_spine.yml`): tabella giornaliera richiesta dal semantic layer di dbt

---

## Spiegazione dei Modelli dbt

Questa sezione spiega **cosa fa ogni modello**, **perché è stato creato così**, e **quale problema della modellazione semantica risolve**.

### Livello 1: Seeds (Dati Grezzi)

I seed sono file CSV caricati direttamente nel database. Rappresentano i **dati sorgente**, senza alcuna trasformazione.

| File                    | Contenuto   | Note                                                   |
| ----------------------- | ----------- | ------------------------------------------------------ |
| `seeds/customers.csv`   | 5 clienti   | Include città per segmentazione                        |
| `seeds/orders.csv`      | 10 ordini   | Stati: 1=pending, 2=processing, 5=shipped, 6=cancelled |
| `seeds/order_lines.csv` | 19 righe    | Include `discount_pct` per sconto per riga             |
| `seeds/products.csv`    | 5 prodotti  | Biciclette e accessori                                 |
| `seeds/categories.csv`  | 5 categorie | Category + subcategory                                 |

**Perché esistono**: Senza dati, non c'è modello. I seeds simulano un database sorgente.

**Come si referenziano**: Nei modelli usi `ref('customers')` — il nome viene dal file CSV (`customers.csv` → `customers`).

---

### Seeds vs Sources: quando usi tabelle reali

In questo corso usiamo **seeds** (CSV caricati da dbt). In produzione, le tabelle esistono già nel database (caricate da un ETL, un altro processo, ecc.). In quel caso si usano le **sources**.

**1. Definisci le sources** in un file YAML, es. `models/staging/_sources.yml`:

```yaml
version: 2

sources:
  - name: raw_data
    schema: public
    tables:
      - name: customers
      - name: orders
      - name: order_lines
      - name: products
      - name: categories
```

**2. Nei modelli usa `source()` invece di `ref()`**:

```sql
-- stg_customers.sql (con sources)
SELECT customer_id, first_name, last_name, email, city
FROM {{ source('raw_data', 'customers') }}
```

|                         | Seeds                | Sources                           |
| ----------------------- | -------------------- | --------------------------------- |
| **Definizione**         | File CSV in `seeds/` | YAML in `sources:`                |
| **Chi crea le tabelle** | dbt (`dbt seed`)     | ETL o altro processo              |
| **Riferimento**         | `ref('customers')`   | `source('raw_data', 'customers')` |

---

### Livello 2: Staging Models

I modelli staging sono il **primo livello di trasformazione**. Sono viste (`view`) che:

- Puliscono i nomi delle colonne
- Normalizzano i tipi di dati
- Arricchiscono con JOIN semplici

**Regola fondamentale**: nello staging **non si aggrega** (niente `GROUP BY` che cambi il grain): una riga della **tabella principale** del modello corrisponde a una riga in uscita. Quella tabella è di solito **un** seed (o una `source`); **JOIN a dimensioni** (lookup) per aggiungere colonne riga per riga sono ammessi — è il caso di `stg_order_lines`, che parte da `order_lines` e arricchisce con `products` e `categories`. Gli altri `stg_*.sql` del corso leggono un solo seed perché non serve altro join a questo livello.

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

**Perché esiste**: Definisce il **contratto** del livello customer. Se domani cambi il nome della colonna `first_name` nel CSV, modifichi solo questo file e tutti i modelli a valle continuano a funzionare.

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

**Perché esiste**: Separa il livello dati grezzi da quello business. Se aggiungi campi al CSV, questo modello li espone o nasconde.

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
    subcategory_id,
    category_id,
    subcategory_name,
    name AS category_name
FROM {{ ref('categories') }}
```

**Cosa fa**: Rinomina `name` in `category_name` per chiarezza. Espone `subcategory_name` per analisi a livello sottocategoria.

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
    ol.line_total,
    ol.discount_pct,
    ol.line_total * (1 - ol.discount_pct) AS net_revenue,
    p.name AS product_name,
    p.category_id,
    p.subcategory_id,
    pc.name AS category_name,
    pc.subcategory_name
FROM {{ ref('order_lines') }} ol
LEFT JOIN {{ ref('products') }} p ON ol.product_id = p.product_id
LEFT JOIN {{ ref('categories') }} pc ON p.subcategory_id = pc.subcategory_id
```

**Cosa fa**:

- JOIN con products e categories per arricchimento
- Calcola `net_revenue` = `line_total * (1 - discount_pct)` — ogni riga ha il proprio sconto

**Perché è importante**:

- Qui vediamo il **pattern fondamentale** dello staging: arricchimento con JOIN
- Il calcolo di `net_revenue` dimostra come si aggiunge **business logic** al livello più basso
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
    c.city,
    o.status,
    o.total AS order_total,
    COUNT(ol.order_line_id) AS line_count,
    SUM(ol.quantity) AS total_items,
    COALESCE(SUM(ol.line_total), 0) AS gross_revenue,
    COALESCE(SUM(ol.net_revenue), 0) AS net_revenue
FROM {{ ref('stg_orders') }} o
LEFT JOIN {{ ref('stg_order_lines') }} ol ON o.order_id = ol.order_id
LEFT JOIN {{ ref('stg_customers') }} c ON o.customer_id = c.customer_id
WHERE o.status = 5  -- Solo ordini spediti
GROUP BY o.order_id, o.order_date, o.customer_id, c.first_name, c.last_name, c.city, o.status, o.total
```

**Cosa calcola**:

- `gross_revenue`: somma dei totali lordi delle righe
- `net_revenue`: somma dei totali netti (con sconti per riga)
- `line_count`: numero di righe per ordine

**Perché `order_total` E `gross_revenue`?**

| Campo           | Sorgente                      | Uso                           |
| --------------- | ----------------------------- | ----------------------------- |
| `order_total`   | `orders.total`                | Per confronto/reconciliazione |
| `gross_revenue` | `SUM(order_lines.line_total)` | Per analisi accurate          |

**Problema che risolve**: Il campo `orders.total` può essere obsoleto o impreciso. Calcolando da `order_lines` otteniamo un valore **riconciliabile**.

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
    COUNT(DISTINCT ol.order_id) AS orders_with_product,
    COALESCE(SUM(ol.quantity), 0) AS units_sold,
    COALESCE(SUM(ol.line_total), 0) AS gross_revenue,
    COALESCE(SUM(ol.net_revenue), 0) AS net_revenue
FROM {{ ref('stg_products') }} p
LEFT JOIN {{ ref('stg_order_lines') }} ol ON p.product_id = ol.product_id
LEFT JOIN {{ ref('stg_categories') }} pc ON p.subcategory_id = pc.subcategory_id
GROUP BY p.product_id, p.name, p.category_id, p.subcategory_id, pc.category_name, pc.subcategory_name
```

**Cosa calcola**:

- `orders_with_product`: quanti ordini contengono questo prodotto (con DISTINCT per evitare fanout)
- `units_sold`: somma delle quantità
- `gross_revenue` / `net_revenue`: revenue con/senza sconti

**Il problema del FANOUT** (concetto chiave):

```
Senza DISTINCT:  Ordine 1 ha 3 prodotti diversi → conta 3 ordini ❌
Con DISTINCT:    Ordine 1 ha 3 prodotti diversi → conta 1 ordine ✅
```

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
    COUNT(DISTINCT o.order_id) AS order_count,
    COALESCE(SUM(o.total), 0) AS lifetime_value,
    COALESCE(SUM(ol.net_revenue), 0) AS lifetime_net_revenue
FROM {{ ref('stg_customers') }} c
LEFT JOIN {{ ref('stg_orders') }} o ON c.customer_id = o.customer_id AND o.status = 5
LEFT JOIN {{ ref('stg_order_lines') }} ol ON o.order_id = ol.order_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.city
```

**Cosa calcola**:

- `order_count`: numero di ordini unici per cliente (solo shipped)
- `lifetime_value`: somma dei totali header (per confronto)
- `lifetime_net_revenue`: somma dei totali netti dalle righe (più accurato)

**Perché due metriche di valore?**

| Metrica                | Calcolo                        | Affidabilità                 |
| ---------------------- | ------------------------------ | ---------------------------- |
| `lifetime_value`       | `SUM(orders.total)`            | Bassa — campo denormalizzato |
| `lifetime_net_revenue` | `SUM(order_lines.net_revenue)` | Alta — calcolato con sconti  |

Il modello espone entrambi per permettere **reconciliazione**.

---

### Livello 4: Layer semantico dbt e MetricFlow

Le fact table incapsulano la logica SQL. Il **semantic layer** di dbt la descrive in modo dichiarativo: per ogni *semantic model* definisci grain, **entità** (chiavi e relazioni), **dimensioni** (incluso il tempo) e **misure** (aggregazioni su colonne o espressioni). Le **metriche** nel YAML referenziano quelle misure e sono ciò che gli strumenti (BI, API, MetricFlow) espongono agli utenti.

**MetricFlow** (`mf`, incluso in `dbt-metricflow`) legge il manifest dbt, valida la semantica rispetto al warehouse e **compila** query che rispettano il grafo (join path, granularità temporale). È il modo standard di provare e documentare le metriche prima di collegarle a un client.

#### Glossario: cosa significano i pezzi dello YAML

Questi termini compaiono in `_semantic_layer.yml` e nella documentazione dbt / MetricFlow. Qui sono legati al nostro esempio `orders_semantic` su `fct_orders`.

| Termine | Ruolo | Esempio nel repo |
| ------- | ----- | ---------------- |
| **Semantic model** | Collega un **modello dbt** (`ref(...)`) a entità, dimensioni e misure in un unico “blocco” semantico. | `orders_semantic` → `ref('fct_orders')` |
| **Grain** | Cosa rappresenta **una riga** della tabella sottostante (la granularità dei dati fisici). Non è una keyword YAML: si desume dal modello e dalle entità. | Una riga = **un ordine** (solo shipped, per come è costruita `fct_orders`) |
| **Entity** | Chiave di business e ruolo nel **grafo** semantico. `primary` = identifica il grain del modello; `foreign` = chiave verso altri semantic model (per join tra modelli, quando li aggiungi). | `order` (primary, `order_id`), `customer` (foreign, `customer_id`) |
| **Dimension** | Attributo su cui **filtrare o raggruppare** (slice). Può essere tempo (`type: time` + granularità) o categorico. | `order_date` (giorno), `city`, `customer_name` |
| **Measure** | **Aggregazione** definita sul semantic model: funzione (`sum`, `count_distinct`, …) + espressione SQL sulle colonne del `ref`. È il mattoncino numerico interno. | `net_revenue` = `sum` di `net_revenue`; `orders_count` = `count_distinct` di `order_id` |
| **Metric** | Nome **esposto** agli utenti e agli strumenti (`mf query`, BI, API). Tipo `simple` → una **measure**; altri tipi combinano metriche già definite (es. `ratio` = numeratore ÷ denominatore). | `total_net_revenue` (`simple` → `net_revenue`); `avg_net_revenue_per_order` (`ratio` → `total_net_revenue` / `order_count`) |
| **Time spine** | Tabella calendario **continua** a una granularità fissa (qui: giorno). Il semantic layer la usa per allineare le metriche nel tempo. | `time_spine_daily` + `_time_spine.yml` |

**Nomi qualificati in `mf query`**: in `--group-by` MetricFlow usa spesso `nome_entità__nome_dimensione` (due underscore), es. `order__city` per la dimensione `city` nel contesto dell’entità `order`. Se sbagli il nome, l’errore della CLI elenca i candidati validi.

**Nota — conteggio ordini (`orders_count`)**: a volte si vede `agg: sum` con `expr: 1` (“somma un 1 per riga”). Con grain **una riga = un ordine** dà lo stesso totale di un conteggio righe, ed è **additivo** come le altre misure `sum`. Qui usiamo invece **`agg: count_distinct` su `order_id`**: significato più chiaro (“ordini unici”), e resta sensato anche se la tabella avesse righe duplicate per errore. `agg: count` su `order_id` conterebbe le righe con id non nullo; con duplicati gonfierebbe, quindi per “numero di ordini” `count_distinct` è la scelta più sicura.

#### Perché MetricFlow (e il semantic layer) oltre alle query sulle fact?

Le fact costruite da dbt **restano indispensabili**: sono la **fonte fisica** nel warehouse, con grain e regole di business testabili (`dbt test`), e vanno benissimo per SQL ad hoc, notebook, pipeline downstream.

**Cosa aggiunge MetricFlow** non è “numeri diversi”, ma un **livello di consumo** diverso:

| Aspetto | Query SQL su `fct_*` | MetricFlow (`mf query`, stesso manifest del Semantic Layer) |
| ------- | -------------------- | ------------------------------------------------------------- |
| **Definizione di “metrica”** | Ogni analista riscrive `SUM(net_revenue)`, `GROUP BY`, filtri tempo; facile divergenza tra report. | Nome stabile (`total_net_revenue`) e definizione **centralizzata** nello YAML: stesso significato per tutti i client. |
| **Metriche composte** | Per un rapporto tipo AOV devi ricordare formula e denominatori coerenti in ogni query. | Es. metrica `ratio` (`avg_net_revenue_per_order`): numeratore/denominatore **già collegati** nel manifest. |
| **Tempo e granularità** | Devi allineare date, spine e `GROUP BY` a mano. | Il layer + time spine supportano slice temporali coerenti con il modello semantico (meno errori di “periodo sbagliato”). |
| **Validazione** | La correttezza è solo disciplina umana e review SQL. | `dbt parse` + `mf validate-configs` controllano definizioni e coerenza con il warehouse **prima** delle query. |
| **Integrazione** | Ottimo per chi scrive SQL. | Stesso catalogo metriche verso **BI, Semantic Layer in cloud, API, agenti** senza duplicare la logica in ogni tool. |

In **questo repository** il dataset è piccolo e c’è un solo semantic model: su `fct_orders` una `SELECT SUM(net_revenue)` è semplice e corretta. Il valore di MetricFlow qui è soprattutto **didattico** e **preparatorio**: in contesti reali, con più team e più modelli collegati, il costo di “ognuno la sua SQL” diventa alto e il layer semantico ripaga.

In questo repository:

| File | Ruolo |
| ---- | ----- |
| `adventureworks/models/marts/_semantic_layer.yml` | Semantic model `orders_semantic` su `ref('fct_orders')` con misure `gross_revenue`, `net_revenue`, `orders_count` e metriche `simple` (`total_net_revenue`, …) più esempio `ratio`: `avg_net_revenue_per_order` |
| `adventureworks/models/marts/time_spine_daily.sql` | Una riga per ogni giorno (DuckDB `generate_series`) |
| `adventureworks/models/marts/_time_spine.yml` | Dichiara il time spine a granularità **day** (`time_spine.standard_granularity_column`) |

**Comandi** (dalla cartella `adventureworks/`; con profilo in root del repo usa `DBT_PROFILES_DIR=..`):

```bash
uv run dbt parse                  # valida modelli + semantic manifest
uv run mf validate-configs        # MetricFlow: semantica + controlli sul warehouse
uv run mf query --metrics total_net_revenue --quiet
uv run mf query --metrics total_net_revenue --group-by order__city
uv run mf query --metrics total_net_revenue --group-by order__order_date__day
uv run mf query --metrics avg_net_revenue_per_order --quiet   # metrica type: ratio
```

Per `group-by`, MetricFlow suggerisce nomi qualificati (es. `order__city`, `order__order_date__day`) quando serve disambiguare rispetto all’entità.

**Nota versioni**: `dbt-metricflow` fissa una combinazione supportata di `dbt-core` e librerie semantiche (in ambiente corso tipicamente la serie 1.10.x). Per altre versioni consulta la [documentazione dbt sul Semantic Layer](https://docs.getdbt.com/docs/build/about-metricflow) e la matrice di compatibilità.

---

## Prima vs Dopo: Riepilogo

La terza colonna è lo strato **opzionale ma consigliato** quando vuoi consumare **metriche nominate** (BI, API, Semantic Layer) oltre alle tabelle fisiche.

| Aspetto          | Prima (SQL diretto)          | Dopo (modelli dbt / fact)      | Dopo (+ MetricFlow / semantic layer)        |
| ---------------- | ---------------------------- | ------------------------------ | ------------------------------------------- |
| **Query**        | Complessa, ripetuta          | `SELECT * FROM fct_xxx`        | `mf query --metrics <nome>` (SQL generata)  |
| **Logica**       | Duplicata in ogni query      | Centralizzata nei `.sql` mart  | Metriche e misure centralizzate nello YAML  |
| **Errori**       | Fanout, DISTINCT dimenticati | Corretto by design sul grain   | Validazione manifest (`parse`, `mf validate-configs`) |
| **Manutenzione** | Difficile                    | Cambi nel modello dbt          | Nomi metrica stabili per più tool / report  |
| **Metriche composte** | Ogni report riscrivie formule | Spesso ancora SQL a mano   | Es. `type: ratio` senza duplicare divisioni |
| **Testing**      | Difficile                    | Test dbt sul modello (vedi sotto) | Più controlli semantici oltre ai test SQL |

---

## Schema.yml: cos'è e perché si crea

Il file `models/schema.yml` (o `schema.yml` nelle sottocartelle di `models/`) è un file di **metadata** che accompagna i modelli e i seed. Non definisce la logica — quella resta nei file SQL e nei CSV — ma aggiunge due cose importanti.

### 1. Documentazione

Descrivi modelli e colonne con `description`. Queste descrizioni compaiono in `dbt docs` (generato con `dbt docs generate` e visualizzato con `dbt docs serve`), così chi usa i dati capisce subito cosa rappresenta ogni tabella e ogni campo.

```yaml
models:
  - name: fct_customers
    description: Fact table clienti. Solo ordini shipped.
    columns:
      - name: lifetime_net_revenue
        description: Somma net_revenue dalle righe (fonte di verità)
```

### 2. Test di qualità dati

Definisci i test (unique, not_null, relationships, ecc.) sulle colonne. Eseguendoli con `dbt test`, dbt controlla che i dati rispettino le regole definite.

```yaml
columns:
  - name: customer_id
    tests:
      - unique
      - not_null
```

### Perché crearlo

- **Onboarding**: nuovi membri del team capiscono il modello dati senza leggere tutto il SQL.
- **Lineage**: `dbt docs` mostra il grafo delle dipendenze tra modelli.
- **Qualità**: i test bloccano modifiche che introducono errori (duplicati, null, relazioni rotte).
- **Manutenzione**: le descrizioni documentano le scelte (es. perché `lifetime_net_revenue` è più affidabile di `lifetime_value`).

I modelli funzionano anche senza `schema.yml`, ma senza documentazione e test il progetto diventa più fragile e difficile da capire.

---

## Test dbt: Cosa sono e a cosa servono

I **test dbt** sono controlli automatici che verificano la qualità e l'integrità dei dati nei tuoi modelli. A differenza dei test unitari nel codice, i test dbt eseguono query SQL sul database e falliscono se i dati non rispettano le regole definite.

### Perché sono utili

- **Catturare errori prima che arrivino agli utenti**: Se un modello produce righe duplicate, valori nulli dove non dovrebbero esserci, o relazioni rotte, il test fallisce e ti avvisa.
- **Documentare le aspettative**: Un test che verifica "customer_id non nullo" documenta implicitamente che quel campo è obbligatorio.
- **Rendere i modelli affidabili**: Con test che passano, puoi fidarti che le fact table rispettano i contratti definiti.

### Tipi di test

1. **Test generici** (schema tests): Si definiscono nel file `schema.yml` accanto al modello. Esempi:
   - `unique`: nessun valore duplicato nella colonna
   - `not_null`: nessun valore NULL
   - `accepted_values`: la colonna contiene solo valori da una lista (es. status in [1,2,5,6])
   - `relationships`: integrità referenziale (es. `customer_id` esiste in `customers`)

2. **Test singolari** (custom): Query SQL personalizzate in file `.sql` che restituiscono le righe che _violano_ la regola. Se la query restituisce 0 righe, il test passa.

### Esempio

```yaml
# In schema.yml
models:
  - name: fct_customers
    columns:
      - name: customer_id
        tests:
          - unique
          - not_null
```

Eseguendo `dbt test`, dbt lancia le query corrispondenti. Se un test fallisce, vedrai quali righe violano la regola.

---

## Esercizi Proposti

### Esercizi base (con i modelli esistenti)

1. **Prodotti per categoria**: Quanti prodotti unici sono stati venduti per categoria? Usa `fct_products` e raggruppa per `category_name`.
2. **Revenue per città**: Quale città ha generato più revenue? Usa `fct_customers` e raggruppa per `city`.
3. **Top clienti**: Chi sono i 3 clienti con il maggior `lifetime_net_revenue`? Query semplice su `fct_customers`.
4. **Prodotti più venduti**: Quali sono i 3 prodotti con più `units_sold`? Usa `fct_products`.

### Esercizi intermedi (query su tabelle raw)

5. **Sconto medio per prodotto**: Qual è il prodotto con lo sconto medio più alto? Usa `order_lines` e calcola `AVG(discount_pct)` per `product_id`.
6. **Reconciliazione**: Confronta `order_total` e `gross_revenue` in `fct_orders`. Ci sono ordini dove differiscono? Perché?
7. **Ordini per stato**: Quanti ordini ci sono per ogni `status`? Usa la tabella `orders` direttamente.

### Esercizi avanzati (modifiche al progetto dbt)

8. **Nuovo mart giornaliero**: Crea `fct_daily_sales` con revenue (gross e net) aggregata per giorno. Parti da `stg_order_lines` e `stg_orders`.
9. **Filtro per data**: Aggiungi un parametro per filtrare gli ordini per anno (es. solo 2024). Usa le [variables dbt](https://docs.getdbt.com/docs/build/jinja-macros#variables).
10. **Test di integrità**: Aggiungi un test dbt che verifica che `gross_revenue` in `fct_orders` sia uguale a `order_total` (a meno di arrotondamenti).

### Esercizi semantic layer / MetricFlow

11. **Query generata**: Esegui `mf query --metrics total_net_revenue --explain` e confronta la SQL mostrata con una `SELECT` manuale su `fct_orders`.
12. **Slice temporale**: Stessa metrica con `--start-time` e `--end-time` in formato ISO8601 su un intervallo che include i tuoi ordini.
13. **Nuova metrica**: Aggiungi in YAML una metrica `simple` basata su `gross_revenue`, esegui `dbt parse` e `mf validate-configs`.

## Guida Rapida

### Eseguire il notebook

```bash
uv run jupyter lab notebooks/01_introduzione.ipynb
```

**Nota**: Esegui il notebook dalla root del progetto. Il notebook si connette a `adventureworks/data/adventureworks.duckdb`. Esegui prima `dbt seed` e `dbt run` dalla cartella `adventureworks/`.

### Comandi dbt

| Comando                | Descrizione                 |
| ---------------------- | --------------------------- |
| `dbt seed`             | Carica i CSV nel database   |
| `dbt run`              | Esegue tutti i modelli      |
| `dbt run -m <modello>` | Esegue un modello specifico |
| `dbt test`             | Esegue i test               |
| `dbt docs generate`    | Genera documentazione       |
| `dbt docs serve`       | Avvia server docs locale    |

**Ricorda**: Esegui i comandi dbt dalla cartella `adventureworks/`.

### Comandi MetricFlow (semantic layer)

| Comando | Descrizione |
| ------- | ----------- |
| `mf validate-configs` | Valida semantic manifest e coerenza con il warehouse |
| `mf query --metrics <nome>` | Esegue una query su una o più metriche (separate da virgola) |
| `mf query ... --group-by order__city` | Raggruppa per dimensione (nomi qualificati come suggeriti dall’errore CLI) |
| `mf query ... --explain` | Mostra la SQL generata |

Usa `uv run mf ...` se MetricFlow non è nel PATH (consigliato in questo progetto).

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
- **10 ordini** (vari stati: pending, processing, shipped, cancelled)
- **19 righe ordine** (con sconti per riga in `discount_pct`)
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

**Problema**: Includere ordini cancellati o pending nelle metriche.

**Soluzione**: Filtra sempre per `status = 5` (shipped). Il campo `status` è numerico, non testuale.

## Risorse

- [dbt Docs](https://docs.getdbt.com/)
- [dbt Semantic Layer / MetricFlow](https://docs.getdbt.com/docs/build/about-metricflow)
- [dbt DuckDB Adapter](https://github.com/duckdb/dbt-duckdb)
- [AdventureWorks Schema](https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure)
