# Phase 0 - Environment Setup
Goal: verify prerequisites and set up local machine to rebuild project.

## Commands (step-by-step)
```bash
#######################################################
# 0. ENV SETUP
# - Homebrew (brew cli package manager)
# - Python3 / Pip3 (using venv)
# - dbt-core / DuckDB / adapter
# - awscli (s3 file retrieval)
# - sqlfluff (git pre-commit hook)
# - genomic tools
#######################################################

# macOS version (any recent macOS is fine)
sw_vers

# Homebrew — package manager. If not installed:
# /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew --version

# Python 3.12 is the sweet spot — broad library compatibility, modern features
# If older than 3.10 or you don't have it:
# brew install python
# OR
# pyenv install 3.12.9
# pyenv local 3.12.9
python3 --version

# Git — for the repo
git --version

# set up project directory
mkdir -p ~/code/1000-genomes-dwh
cd ~/code/1000-genomes-dwh

# initialize repo
git init
git branch -M main

# create .gitignore
cat > .gitignore <<'EOF'
# Python
__pycache__/
*.py[cod]
.venv/
venv/
.env
.envrc
*.egg-info/

# dbt
target/
dbt_packages/
logs/
.user.yml

# DuckDB (warehouse files can get huge — never commit)
*.duckdb
*.duckdb.wal
*.duckdb.tmp

# Raw data — keep out of git
data/raw/*
!data/raw/SLICE.md
bronze/
*.vcf
*.vcf.gz
*.bam
*.cram
*.bcf

# macOS / IDE noise
.DS_Store
.vscode/
.idea/
EOF

# create initial README and first commit
echo "# 1000 Genomes Data Warehouse" > README.md
git add .gitignore README.md
git commit -m "Initial commit: gitignore + README"

# setup python virtual environment
python3 -m venv .venv
source .venv/bin/activate
which python3
python3 --version

# always upgrade pip first in fresh env (and to minimize warnings)
pip install --upgrade pip

# install dbt core (via DuckDB adapter) and python deps
pip install "mashumaro<3.15" # max version for dbt-core (as of 5/2026)
pip install dbt-duckdb

# Bioinformatics + data tooling
pip install cyvcf2 pysam pandas pyarrow faker numpy

# Verify
dbt --version
# Core:
#   - installed: 1.11.11
#   - latest:    1.11.11 - Up to date!
# 
# Plugins:
#   - duckdb: 1.10.1 - Up to date!

# Pin everything for reproducibility
pip freeze > requirements.txt
git add requirements.txt
git commit -m "Add Python dependencies"

# install DuckDB CLI
brew install duckdb
duckdb --version  # v1.5.3 (Variegata)

# create database
duckdb warehouse.duckdb

# initialize dbt
dbt init
# genomics_dwh
# 1 (duckdb)

# fix profiles.yml to use an absolute path
echo $HOME   # e.g., /Users/yourusername

# create sanitized profiles example file for repo
cat > genomics_dwh/profiles.yml.example <<'EOF'
# This file is for documentation/onboarding only. dbt does NOT read this file.
# To use: copy the contents into ~/.dbt/profiles.yml, then update `path` below
# to the absolute path of warehouse.duckdb on your machine.
#
# When you add Snowflake (Phase 7), add a `prod` output alongside `dev`.

genomics_dwh:
  target: dev
  outputs:
    dev:
      type: duckdb
      # Replace with absolute path on your machine, e.g.
      # /Users/yourname/code/1000-genomes-dwh/warehouse.duckdb
      path: /ABSOLUTE/PATH/TO/1000-genomes-dwh/warehouse.duckdb
      threads: 4
EOF

# change to dbt directory
cd genomics_dwh

# verify dbt config
dbt debug
# Expect: "All checks passed!"

# Run example models that dbt init created
dbt run
# Expect: "Completed successfully" (2 models built ...)

# Verify DuckDB and warhouse outside dbt directory
duckdb ../warehouse.duckdb -c "SHOW TABLES"
# Expect
# ┌─────────────────────┐
# │        name         │
# │       varchar       │
# ├─────────────────────┤
# │ my_first_dbt_model  │
# │ my_second_dbt_model │
# └─────────────────────┘

# CONGRATS! dbt and DuckDB configured correct.

# return to project root and verify AWS access and DuckDB httpfs
cd ..
brew install awscli

# Top-level prefixes — should show 'data/' and similar
aws s3 ls --no-sign-request s3://1000genomes-dragen/

# DRAGEN version directories
aws s3 ls --no-sign-request s3://1000genomes-dragen/data/

# A specific sample (HG00096 is the canonical first 1KG sample)
aws s3 ls --no-sign-request s3://1000genomes-dragen/data/dragen-3.5.7b/hg38_altaware_nohla-cnv-anchored/HG00096/ | head

# DuckDB httpfs and test Python connectivity to database
python << PY
import duckdb
con = duckdb.connect()
con.execute("INSTALL httpfs; LOAD httpfs;")

# Plain HTTPS — no S3 signing required
result = con.execute("""
    SELECT count(*) FROM read_parquet(
      'https://github.com/duckdb/duckdb/raw/main/data/parquet-testing/userdata1.parquet'
    )
""").fetchone()
print(f"httpfs works — row count: {result[0]:,}")
PY
# Expect: "httpfs works — row count: 1,000"

# delete dbt example scaffolding
rm -rf genomics_dwh/models/example

# pre-commit + sqlfluff configured for dbt (catch SQL issues before commits)
pip install pre-commit sqlfluff sqlfluff-templater-dbt

# Pre-commit hook config — note the additional_dependencies block, which tells
# pre-commit's sandboxed virtualenv to also install sqlfluff-templater-dbt and
# the dbt-duckdb adapter. Without those, the dbt templater can't run in the hook.
cat > .pre-commit-config.yaml <<'EOF'
repos:
  - repo: https://github.com/sqlfluff/sqlfluff
    rev: 3.0.7
    hooks:
      - id: sqlfluff-lint
        files: \.sql$
        additional_dependencies:
          - sqlfluff-templater-dbt
          - dbt-duckdb
EOF

# sqlfluff config
cat > .sqlfluff <<'EOF'
[sqlfluff]
# Templater: 'dbt' compiles via your dbt project so macros and packages resolve correctly.
# Slower than 'jinja' (per-file dbt invocation) but accurate. Requires sqlfluff-templater-dbt
# installed in the venv AND in pre-commit's hook sandbox (declared in .pre-commit-config.yaml).
templater = dbt
dialect = duckdb
runaway_limit = 10
max_line_length = 120
indent_unit = space

# Rules that tend to fight common dbt and genomics patterns:
# - AM04: ambiguous column references in `select * from cte` (dbt pattern)
# - ST06: column ordering preferences (dbt pattern)
# - RF02: qualified column references in single-table queries (dbt pattern)
# - RF04: reserved words as identifiers (we use 'position' — universal in bioinformatics)
exclude_rules = AM04, ST06, RF02, RF04

[sqlfluff:indentation]
tab_space_size = 4

# dbt templater config — tells sqlfluff where the dbt project is, since pre-commit
# runs hooks from the repo root but the dbt project is in a subdirectory.
[sqlfluff:templater:dbt]
project_dir = ./genomics_dwh
profiles_dir = ~/.dbt

# Jinja templater config — kept for reference even though we're not using it as the
# active templater. If you ever switch back (templater = jinja above), this enables
# awareness of dbt's built-in Jinja functions.
[sqlfluff:templater:jinja]
apply_dbt_builtins = true

# Capitalization conventions matching dbt's modern style guide.
# Lowercase keywords (`select`, not `SELECT`), identifiers, and functions.
[sqlfluff:rules:capitalisation.keywords]
capitalisation_policy = lower

[sqlfluff:rules:capitalisation.identifiers]
extended_capitalisation_policy = lower

[sqlfluff:rules:capitalisation.functions]
extended_capitalisation_policy = lower

[sqlfluff:rules:capitalisation.literals]
capitalisation_policy = lower

[sqlfluff:rules:capitalisation.types]
extended_capitalisation_policy = lower
EOF

# Ignore dbt's compiled output and any future scaffolding
cat > .sqlfluffignore << EOF
target/
dbt_packages/
logs/
**/example/
EOF

# install git hook
pre-commit install  # pre-commit installed at .git/hooks/pre-commit

# commit initialized project
git add .
git commit -m "Initialize dbt project (genomics_dws) with DuckDB target and sqlfluff config"
# [INFO] Initializing environment for https://github.com/sqlfluff/sqlfluff.
# [INFO] Initializing environment for https://github.com/sqlfluff/sqlfluff:sqlfluff-templater-dbt,dbt-duckdb.
# [INFO] Installing environment for https://github.com/sqlfluff/sqlfluff.
# [INFO] Once installed this environment will be reused.
# [INFO] This may take a few minutes...
# sqlfluff-lint........................................(no files to check)Skipped
```