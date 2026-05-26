{% macro make_variant_key(chrom='chromosome', pos='position', ref='ref_allele', alt='alt_allele') %}
    {{ chrom }} || '_' || {{ pos }} || '_' || {{ ref }} || '_' || {{ alt }}
{% endmacro %}
