# Dockerfile — Code Location per Dagster
#
# Questo container serve il codice del pipeline via gRPC.
# Il daemon e il webserver si connettono a questa porta per:
#   - scoprire asset, job, schedule e sensor definiti in dagster_pipeline.py
#   - eseguire le valutazioni dei sensor tick
#   - avviare i run
#
# La stessa immagine viene usata da tutti e tre i servizi in docker-compose.yml;
# il comando di avvio cambia a seconda del servizio (CMD override).
#
# Build context: root del repo (non lezione2/), perché adventureworks/ è alla root.
#
#   docker build -f lezione2/Dockerfile -t adventureworks-dagster .

FROM python:3.12-slim

WORKDIR /app

# uv: installazione dipendenze più veloce di pip con lock file
RUN pip install uv --no-cache-dir

# --- Dipendenze prima del codice ---
# Separare COPY pyproject.toml/uv.lock dal COPY del codice sorgente
# permette a Docker di riusare questo layer finché le dipendenze non cambiano,
# anche se si modifica dagster_pipeline.py.
COPY pyproject.toml uv.lock ./
RUN uv sync --extra dagster

# --- Codice sorgente ---
COPY profiles.yml ./
COPY adventureworks/ ./adventureworks/
COPY lezione2/dagster_pipeline.py ./lezione2/dagster_pipeline.py

# --- Configurazione Dagster ---
# dagster.yaml: storage PostgreSQL + run launcher
# workspace.yaml: dice al daemon dove trovare questo code location via gRPC
COPY lezione2/dagster.yaml ./dagster.yaml
COPY lezione2/workspace.yaml ./workspace.yaml

# --- dbt compile al BUILD TIME ---
# @dbt_assets in dagster_pipeline.py legge manifest.json al momento del caricamento
# del modulo Python. Il compile deve essere fatto prima che il server parta.
# Vantaggio: se i modelli dbt hanno errori di sintassi, il build fallisce subito
# invece di farlo scoprire solo quando il container è già in esecuzione.
RUN cd adventureworks && uv run dbt compile --profiles-dir ..

# DAGSTER_HOME: cartella dove Dagster cerca dagster.yaml e workspace.yaml
# Esegui come utente non-root: principio del minimo privilegio.
# Se il container venisse compromesso, l'attaccante non avrebbe accesso root all'host.
RUN useradd --no-create-home --shell /bin/false dagster \
    && chown -R dagster:dagster /app

USER dagster

ENV DAGSTER_HOME=/app

# Porta gRPC del code location server
EXPOSE 4000

# Verifica che la porta gRPC sia raggiungibile.
# /dev/tcp è una feature bash built-in: nessun tool extra richiesto.
# --start-period=30s lascia tempo al code-server di caricare il manifest dbt.
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
    CMD bash -c 'echo > /dev/tcp/localhost/4000' || exit 1

# Comando default: avvia il code location server.
# Viene sovrascritto in docker-compose per daemon (dagster-daemon run)
# e per webserver (dagster-webserver).
CMD ["uv", "run", "dagster", "code-server", "start", \
     "--python-file", "lezione2/dagster_pipeline.py", \
     "--host", "0.0.0.0", \
     "--port", "4000"]
