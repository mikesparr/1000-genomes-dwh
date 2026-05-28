# Phase 9 - Dagster Orchestration
**Goal:** orchestrate running of data pipeline by wrapping Python ingestion 
and entire dbt project as a single asset graph, with serial dependencies.

## Example
![Dagster Run](assets/dagster-run.png)

## Commands (step-by-step)
```bash
#######################################################
# 9. OPTIONAL
# - Dagster orchestration
#######################################################

# from repo root, install dagster and modules
pip install dagster dagster-webserver dagster-dbt dagster-duckdb dagster-dg-cli
mkdir -p orchestrator

# update requirements
pip freeze > requirements.txt

# create orchestrator/definitions.py
cat > orchestrator/definitions.py <<'EOF'
from pathlib import Path
import subprocess

import dagster as dg
from dagster_dbt import DbtCliResource, DbtProject, dbt_assets

REPO_ROOT = Path(__file__).parent.parent
DBT_PROJECT_PATH = REPO_ROOT / "genomics_dwh"

dbt_project = DbtProject(project_dir=DBT_PROJECT_PATH)
dbt_project.prepare_if_dev()


@dg.asset(compute_kind="python", group_name="ingestion")
def raw_vcfs(context: dg.AssetExecutionContext) -> None:
    """Phase 1 — download 1KG VCFs and extract chr22."""
    subprocess.run(["python", "loader/fetch_1kg_data.py"], cwd=REPO_ROOT, check=True)
    subprocess.run(["python", "loader/extract_region.py"], cwd=REPO_ROOT, check=True)


@dg.multi_asset(
    specs=[
        dg.AssetSpec("raw_1kg__samples", group_name="ingestion", deps=[raw_vcfs]),
        dg.AssetSpec("raw_1kg__variants", group_name="ingestion", deps=[raw_vcfs]),
        dg.AssetSpec("raw_ref__genes", group_name="ingestion", deps=[raw_vcfs]),
        dg.AssetSpec("raw_ref__clinvar", group_name="ingestion", deps=[raw_vcfs]),
    ],
    compute_kind="python",
    can_subset=False,
)
def bronze_parquet_assets(context: dg.AssetExecutionContext):
    """Phase 2 — convert chr22 VCFs and reference data to Bronze Parquet."""
    subprocess.run(["python", "loader/vcf_to_parquet.py"], cwd=REPO_ROOT, check=True)
    subprocess.run(["python", "loader/panel_to_parquet.py"], cwd=REPO_ROOT, check=True)
    subprocess.run(["python", "loader/reference_to_parquet.py"], cwd=REPO_ROOT, check=True)
    for spec in [
        "raw_1kg__samples",
        "raw_1kg__variants",
        "raw_ref__genes",
        "raw_ref__clinvar",
    ]:
        yield dg.MaterializeResult(asset_key=spec)


@dg.multi_asset(
    specs=[
        dg.AssetSpec(
            "raw_synth__patients",
            group_name="synth",
            deps=[dg.AssetKey("raw_1kg__samples")],
        ),
        dg.AssetSpec(
            "raw_synth__panels",
            group_name="synth",
            deps=[dg.AssetKey("raw_1kg__samples")],
        ),
        dg.AssetSpec(
            "raw_synth__mrd_tests",
            group_name="synth",
            deps=[dg.AssetKey("raw_1kg__samples")],
        ),
        dg.AssetSpec(
            "raw_synth__mrd_detections",
            group_name="synth",
            deps=[dg.AssetKey("raw_1kg__samples")],
        ),
        dg.AssetSpec(
            "raw_synth__clinical_events",
            group_name="synth",
            deps=[dg.AssetKey("raw_1kg__samples")],
        ),
    ],
    compute_kind="python",
    can_subset=False,
)
def synthetic_data_assets(context: dg.AssetExecutionContext):
    """Phase 3 — generate synthetic patients, panels, MRD trajectories."""
    for script in [
        "synth/generate_patients.py",
        "synth/generate_panels.py",
        "synth/generate_trajectories.py",
        "synth/synth_to_parquet.py",
    ]:
        subprocess.run(["python", script], cwd=REPO_ROOT, check=True)
    for spec in [
        "raw_synth__patients",
        "raw_synth__panels",
        "raw_synth__mrd_tests",
        "raw_synth__mrd_detections",
        "raw_synth__clinical_events",
    ]:
        yield dg.MaterializeResult(asset_key=spec)


@dbt_assets(manifest=dbt_project.manifest_path)
def dbt_models(context: dg.AssetExecutionContext, dbt: DbtCliResource):
    """Phases 4-6 — staging, intermediate, marts, snapshot."""
    yield from dbt.cli(["build"], context=context).stream()


defs = dg.Definitions(
    assets=[raw_vcfs, bronze_parquet_assets, synthetic_data_assets, dbt_models],
    resources={"dbt": DbtCliResource(project_dir=DBT_PROJECT_PATH)},
)
EOF

# update .gitignore
echo "\n# Dagster\norchestrator/.*" >> .gitignore

# add meta definitions to dbt staging sources
cat > genomics_dwh/models/staging/_sources.yml <<'EOF'
version: 2

sources:
  - name: bronze
    description: "Lakehouse Bronze layer — Parquet files produced by Phase 2 and 3 loaders."
    config:
      meta:
        external_location: "read_parquet('{{ env_var('DWH_REPO_ROOT', '..') }}/bronze/{name}.parquet')"
    tables:
      - name: raw_1kg__samples
        description: "1000 Genomes sample panel (population, sex, family)"
        columns:
          - name: sample
            tests: [not_null, unique]
        meta:
          dagster:
            asset_key: ["raw_1kg__samples"]

      - name: raw_synth__patients
        description: "Synthetic patient demographics"
        columns:
          - name: patient_id
            tests: [not_null, unique]
          - name: sample_id_1kg
            tests: [not_null]
          - name: stage_at_diagnosis
            tests:
              - accepted_values:
                  arguments:
                    values: ['I', 'II', 'III', 'IV']
        meta:
          dagster:
            asset_key: ["raw_synth__patients"]

      - name: raw_synth__panels
        description: "Synthetic personalized panels (16 variants per patient)"
        columns:
          - name: patient_id
            tests: [not_null]
          - name: variant_key
            tests: [not_null]
        meta:
          dagster:
            asset_key: ["raw_synth__panels"]

      - name: raw_synth__mrd_tests
        description: "Synthetic serial MRD test events"
        columns:
          - name: test_id
            tests: [not_null, unique]
        meta:
          dagster:
            asset_key: ["raw_synth__mrd_tests"]

      - name: raw_synth__mrd_detections
        description: "Synthetic per-variant detection signals at each MRD test"
        columns:
          - name: detection_id
            tests: [not_null, unique]
        meta:
          dagster:
            asset_key: ["raw_synth__mrd_detections"]

      - name: raw_synth__clinical_events
        description: "Synthetic clinical events (diagnosis, surgery, chemo, recurrence)"
        columns:
          - name: event_id
            tests: [not_null, unique]
        meta:
          dagster:
            asset_key: ["raw_synth__clinical_events"]

      - name: raw_ref__genes
        description: "GENCODE gene annotation, chr22 only"
        meta:
          dagster:
            asset_key: ["raw_ref__genes"]

      - name: raw_ref__clinvar
        description: "ClinVar variant clinical significance, chr22 only"
        meta:
          dagster:
            asset_key: ["raw_ref__clinvar"]

  # The variant Parquet is hive-partitioned, so it needs a different read pattern.
  - name: bronze_variants
    description: "Per-sample chr22 variant Parquet (hive-partitioned)."
    config:
      meta:
        external_location: "read_parquet('{{ env_var('DWH_REPO_ROOT', '..') }}/bronze/raw_1kg__variants/**/*.parquet', hive_partitioning=true)"
    tables:
      - name: raw_1kg__variants
        description: "Per-sample chr22 variants from 1KG DRAGEN reanalysis"
        columns:
          - name: chromosome
            tests: [not_null]
          - name: position
            tests: [not_null]
          - name: sample_id
            tests: [not_null]
        meta:
          dagster:
            asset_key: ["raw_1kg__variants"]
EOF

# re-parse dbt
cd genomics_dwh
dbt parse

# set up dagster dir
cd ../orchestrator
DAGSTER_HOME="$(pwd)/.dagster_home"
mkdir -p "$DAGSTER_HOME"

# run dagster webserver visible at http://localhost:3000
dg dev -f definitions.py
# CTRL+C to stop

# add workflows for dag validation and sql lint
cd ..
cat > .github/workflows/lint-sql.yml <<'EOF'
name: Lint SQL with sqlfluff

on:
  push:
    branches:
      - main
    paths:
      - 'genomics_dwh/**/*.sql'
      - 'genomics_dwh/dbt_project.yml'
      - 'genomics_dwh/packages.yml'
      - '.sqlfluff'
      - '.sqlfluffignore'
      - '.pre-commit-config.yaml'
  pull_request:
    paths:
      - 'genomics_dwh/**/*.sql'
      - 'genomics_dwh/dbt_project.yml'
      - 'genomics_dwh/packages.yml'
      - '.sqlfluff'
      - '.sqlfluffignore'
      - '.pre-commit-config.yaml'
  workflow_dispatch:

jobs:
  sqlfluff-lint:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: 'pip'

      - name: Install dependencies
        # Matches the additional_dependencies in .pre-commit-config.yaml so the
        # dbt templater works the same way locally and in CI.
        run: |
          pip install --upgrade pip
          pip install \
            sqlfluff==3.0.7 \
            sqlfluff-templater-dbt \
            dbt-duckdb

      - name: Install dbt packages
        # Required so that {{ dbt_utils.* }} references resolve during templating.
        working-directory: ./genomics_dwh
        run: dbt deps

      - name: Generate dbt manifest
        # The dbt templater needs a fresh manifest. --no-compile skips the
        # database-touching compile step that isn't needed for templating.
        working-directory: ./genomics_dwh
        env:
          DWH_REPO_ROOT: ${{ github.workspace }}
        run: dbt parse --profiles-dir .

      - name: Run sqlfluff lint
        env:
          DWH_REPO_ROOT: ${{ github.workspace }}
        # Lint everything sqlfluff would lint locally. The .sqlfluff config at
        # the repo root, the .sqlfluffignore exclusions, and the dbt templater
        # all work the same way as they do in pre-commit.
        run: sqlfluff lint genomics_dwh/
EOF

cat > .github/workflows/validate-dagster.yml <<'EOF'
name: Validate Dagster Definitions

on:
  push:
    branches:
      - main
    paths:
      - 'loader/**'
      - 'synth/**'
      - 'orchestrator/**'
      - 'genomics_dwh/models/**'
      - 'genomics_dwh/macros/**'
      - 'genomics_dwh/dbt_project.yml'
      - 'genomics_dwh/packages.yml'
      - 'genomics_dwh/profiles.yml'
  pull_request:
    paths:
      - 'loader/**'
      - 'synth/**'
      - 'orchestrator/**'
      - 'genomics_dwh/models/**'
      - 'genomics_dwh/macros/**'
      - 'genomics_dwh/dbt_project.yml'
      - 'genomics_dwh/packages.yml'
      - 'genomics_dwh/profiles.yml'
  workflow_dispatch:

jobs:
  validate-dagster:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install Python dependencies
        run: |
          pip install --upgrade pip
          pip install \
            dbt-duckdb \
            dagster \
            dagster-webserver \
            dagster-dg-cli \
            dagster-dbt \
            dagster-duckdb

      - name: Install dbt packages
        working-directory: ./genomics_dwh
        run: dbt deps

      - name: Generate dbt manifest
        working-directory: ./genomics_dwh
        env:
          DWH_REPO_ROOT: ${{ github.workspace }}
        run: dbt parse --profiles-dir .

      - name: Validate Dagster definitions load
        working-directory: ./orchestrator
        env:
          DWH_REPO_ROOT: ${{ github.workspace }}
        # Use `dagster definitions validate -f` rather than `dg check defs` because
        # this project uses a file-based layout (-f definitions.py), not the
        # scaffolded dg project layout (which requires a dg.toml / pyproject.toml).
        # Local dev still uses `dg dev` for the interactive UI; CI uses the
        # file-based validator that matches our layout.
        run: dagster definitions validate -f definitions.py
EOF

# commit changes
git add .gitignore requirements.txt orchestrator/definitions.py
git add genomics_dwh/models/staging/_sources.yml .github/workflows/*.yml
git commit -m "Add Dagster orchestration and validation workflows"
```