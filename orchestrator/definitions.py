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
