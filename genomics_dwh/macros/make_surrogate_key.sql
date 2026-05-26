{# Wraps dbt_utils.generate_surrogate_key but stays portable if you swap utils packages later. #}
{% macro make_surrogate_key(columns) %}
    md5(
      {% for col in columns -%}
        coalesce(cast({{ col }} as varchar), '_NULL_')
        {%- if not loop.last %} || '_' || {% endif %}
      {%- endfor %}
    )
{% endmacro %}
