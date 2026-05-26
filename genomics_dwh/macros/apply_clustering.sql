{# Returns the right config block for the current target — Snowflake gets cluster_by,
   DuckDB gets nothing (we handle ordering in the model SQL via ORDER BY). #}
{% macro apply_clustering(cluster_cols) %}
  {% if target.type == 'snowflake' %}
    {{ return(config(cluster_by=cluster_cols)) }}
  {% endif %}
{% endmacro %}
