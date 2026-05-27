
## q01_pathogenic_variants_in_genes_by_ancestry
```
┌─────────────┬─────────────┬────────────┬──────────┬────────────┬────────────┬─────────┬──────────────────────┬───────────────────────┬──────────────────┬────────────────────────┬──────────┬─────────────────┐
│ gene_symbol │ variant_key │ chromosome │ position │ ref_allele │ alt_allele │  rsid   │ clinvar_significance │ clinvar_disease_names │ super_population │ n_samples_with_variant │ mean_vaf │ mean_read_depth │
│   varchar   │   varchar   │  varchar   │  int64   │  varchar   │  varchar   │ varchar │       varchar        │        varchar        │     varchar      │         int64          │  double  │     double      │
└─────────────┴─────────────┴────────────┴──────────┴────────────┴────────────┴─────────┴──────────────────────┴───────────────────────┴──────────────────┴────────────────────────┴──────────┴─────────────────┘
                                                                                                     0 rows                                                                                                    
```

## q02_allele_frequency_by_population
```
┌────────────────────┬──────────────────┬───────────┬──────────────────┬─────────────────────┬──────────────────┬──────────────────────┬────────────────────┐
│    variant_key     │ super_population │ n_samples │ alt_allele_total │ called_allele_total │ allele_frequency │ homozygous_alt_count │ heterozygous_count │
│      varchar       │     varchar      │   int64   │      int128      │       int128        │      double      │        int128        │       int128       │
├────────────────────┼──────────────────┼───────────┼──────────────────┼─────────────────────┼──────────────────┼──────────────────────┼────────────────────┤
│ chr22_15528427_C_T │ EUR              │         1 │                0 │                   2 │              0.0 │                    0 │                  0 │
│ chr22_15528427_C_T │ EAS              │         1 │                0 │                   2 │              0.0 │                    0 │                  0 │
└────────────────────┴──────────────────┴───────────┴──────────────────┴─────────────────────┴──────────────────┴──────────────────────┴────────────────────┘
```

## q03_mrd_positivity_by_landmark
```
┌───────────────┬────────────────────┬────────────┬──────────────┬───────────────┬──────────────────┬───────────────┬────────────────┬───────────────────┬───────────────┬────────────────┬───────────────────┬───────────────┬────────────────┬───────────────────┐
│  tumor_type   │ stage_at_diagnosis │ n_patients │ positive_d90 │ evaluable_d90 │ pct_positive_d90 │ positive_d180 │ evaluable_d180 │ pct_positive_d180 │ positive_d365 │ evaluable_d365 │ pct_positive_d365 │ positive_d730 │ evaluable_d730 │ pct_positive_d730 │
│    varchar    │      varchar       │   int64    │    int128    │    int128     │      double      │    int128     │     int128     │      double       │    int128     │     int128     │      double       │    int128     │     int128     │      double       │
├───────────────┼────────────────────┼────────────┼──────────────┼───────────────┼──────────────────┼───────────────┼────────────────┼───────────────────┼───────────────┼────────────────┼───────────────────┼───────────────┼────────────────┼───────────────────┤
│ bladder       │ II                 │          1 │            0 │             1 │              0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │
│ breast        │ I                  │          1 │            0 │             1 │              0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │
│ breast        │ II                 │          2 │            0 │             2 │              0.0 │             0 │              2 │               0.0 │             0 │              2 │               0.0 │             0 │              2 │               0.0 │
│ breast        │ III                │          3 │            0 │             3 │              0.0 │             0 │              3 │               0.0 │             1 │              3 │              33.3 │             0 │              2 │               0.0 │
│ breast        │ IV                 │          3 │            1 │             3 │             33.3 │             2 │              3 │              66.7 │             1 │              2 │              50.0 │             1 │              1 │             100.0 │
│ colorectal    │ I                  │          5 │            0 │             5 │              0.0 │             0 │              5 │               0.0 │             0 │              5 │               0.0 │             0 │              5 │               0.0 │
│ colorectal    │ II                 │          4 │            0 │             4 │              0.0 │             0 │              4 │               0.0 │             1 │              4 │              25.0 │             2 │              4 │              50.0 │
│ colorectal    │ III                │          4 │            0 │             4 │              0.0 │             1 │              4 │              25.0 │             2 │              4 │              50.0 │             0 │              2 │               0.0 │
│ colorectal    │ IV                 │          2 │            1 │             2 │             50.0 │             1 │              2 │              50.0 │             0 │              1 │               0.0 │             1 │              1 │             100.0 │
│ head_and_neck │ III                │          1 │            0 │             1 │              0.0 │             0 │              1 │               0.0 │             1 │              1 │             100.0 │             1 │              1 │             100.0 │
│ head_and_neck │ IV                 │          1 │            0 │             1 │              0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │             0 │              0 │              NULL │
│ lung_nsclc    │ I                  │          1 │            0 │             1 │              0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │
│ lung_nsclc    │ II                 │          1 │            0 │             1 │              0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │
│ lung_nsclc    │ III                │          2 │            0 │             2 │              0.0 │             0 │              2 │               0.0 │             0 │              2 │               0.0 │             1 │              2 │              50.0 │
│ lung_nsclc    │ IV                 │          1 │            1 │             1 │            100.0 │             1 │              1 │             100.0 │             0 │              0 │              NULL │             0 │              0 │              NULL │
│ melanoma      │ I                  │          3 │            0 │             3 │              0.0 │             0 │              3 │               0.0 │             0 │              3 │               0.0 │             0 │              3 │               0.0 │
│ melanoma      │ II                 │          1 │            0 │             1 │              0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │             1 │              1 │             100.0 │
│ melanoma      │ IV                 │          1 │            0 │             1 │              0.0 │             1 │              1 │             100.0 │             0 │              0 │              NULL │             0 │              0 │              NULL │
│ ovarian       │ III                │          1 │            0 │             1 │              0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │             1 │              1 │             100.0 │
│ pancreatic    │ III                │          1 │            0 │             1 │              0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │
│ pancreatic    │ IV                 │          2 │            1 │             2 │             50.0 │             1 │              2 │              50.0 │             0 │              1 │               0.0 │             0 │              0 │              NULL │
│ prostate      │ I                  │          5 │            0 │             5 │              0.0 │             1 │              5 │              20.0 │             1 │              5 │              20.0 │             0 │              4 │               0.0 │
│ prostate      │ III                │          1 │            0 │             1 │              0.0 │             0 │              1 │               0.0 │             1 │              1 │             100.0 │             0 │              0 │              NULL │
│ renal         │ I                  │          2 │            0 │             2 │              0.0 │             0 │              2 │               0.0 │             0 │              2 │               0.0 │             1 │              2 │              50.0 │
│ renal         │ IV                 │          1 │            0 │             1 │              0.0 │             0 │              1 │               0.0 │             0 │              1 │               0.0 │             1 │              1 │             100.0 │
└───────────────┴────────────────────┴────────────┴──────────────┴───────────────┴──────────────────┴───────────────┴────────────────┴───────────────────┴───────────────┴────────────────┴───────────────────┴───────────────┴────────────────┴───────────────────┘
  25 rows                                                                                                                                                                                                                                               15 columns
```

## q04_mrd_lead_time_analysis
```
┌────────────────────┬────────────┬───────────────┬──────────────────┬───────────────┬───────────────┬─────────────────┬────────────────────┬──────────────┬──────────────┐
│ stage_at_diagnosis │ n_patients │ avg_lead_days │ median_lead_days │ min_lead_days │ max_lead_days │ avg_lead_months │ median_lead_months │ q1_lead_days │ q3_lead_days │
│      varchar       │   int64    │    double     │      double      │     int64     │     int64     │     double      │       double       │    double    │    double    │
├────────────────────┼────────────┼───────────────┼──────────────────┼───────────────┼───────────────┼─────────────────┼────────────────────┼──────────────┼──────────────┤
│ I                  │          2 │         315.0 │            315.0 │           270 │           360 │            10.5 │               10.5 │        292.5 │        337.5 │
│ II                 │          7 │         411.4 │            360.0 │           270 │           630 │            13.7 │               12.0 │        315.0 │        495.0 │
│ III                │         10 │         261.0 │            270.0 │           180 │           450 │             8.7 │                9.0 │        180.0 │        270.0 │
│ IV                 │         11 │         130.9 │             90.0 │            90 │           180 │             4.4 │                3.0 │         90.0 │        180.0 │
└────────────────────┴────────────┴───────────────┴──────────────────┴───────────────┴───────────────┴─────────────────┴────────────────────┴──────────────┴──────────────┘
```

## q05_biostats_feature_matrix
```
┌──────────────────────────────────┬──────────────────┬──────────────┬───────────────────────────┬───────────────┬────────────────────┬─────────────┬───────────────┬─────────────────────┬────────────────────┬─────────────────────┬─────────────────────┬────────────────┬────────────────────┬───────────────────────┬──────────────┐
│        patient_sk_masked         │ age_at_diagnosis │ sex_at_birth │ ancestry_super_population │  tumor_type   │ stage_at_diagnosis │  trial_id   │ treatment_arm │ baseline_panel_size │ mrd_status_d90_int │ mrd_status_d180_int │ mrd_status_d365_int │ event_observed │ time_to_event_days │ recurrence_within_2yr │ event_status │
│             varchar              │      int32       │   varchar    │          varchar          │    varchar    │      varchar       │   varchar   │    varchar    │        int32        │       int32        │        int32        │        int32        │     int32      │       int64        │        boolean        │   varchar    │
├──────────────────────────────────┼──────────────────┼──────────────┼───────────────────────────┼───────────────┼────────────────────┼─────────────┼───────────────┼─────────────────────┼────────────────────┼─────────────────────┼─────────────────────┼────────────────┼────────────────────┼───────────────────────┼──────────────┤
│ 00788683e6256ff069785dea618d8750 │               65 │ male         │ EUR                       │ colorectal    │ IV                 │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              1 │                720 │ true                  │ event        │
│ 0202af1b535039963977ae2198095af5 │               63 │ male         │ AMR                       │ lung_nsclc    │ I                  │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ 07786236e5d49b3135d058ee9e4a88a4 │               55 │ female       │ SAS                       │ head_and_neck │ III                │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   1 │              1 │                720 │ true                  │ event        │
│ 0a60305820dfc485e0eb0f7d8872baf8 │               40 │ male         │ EUR                       │ lung_nsclc    │ IV                 │ NCT33333333 │ experimental  │                  16 │                  1 │                   1 │                NULL │              1 │                180 │ true                  │ event        │
│ 0b7e5f1a6f57d53cd693363c67fee221 │               53 │ male         │ AFR                       │ colorectal    │ II                 │ NCT33333333 │ experimental  │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ 0bf9821317c49058689b6e908a28708a │               45 │ female       │ AMR                       │ breast        │ II                 │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ 0ce9ffd8c0d1bca1b887c151dee0eb9f │               67 │ male         │ AFR                       │ colorectal    │ I                  │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ 0f7718c4a4e140711800c02b0136ec62 │               48 │ male         │ AFR                       │ melanoma      │ IV                 │ NULL        │ NULL          │                  16 │                  0 │                   1 │                NULL │              1 │                270 │ true                  │ event        │
│ 1aca6c466b50af34679ae6c2c361906c │               57 │ female       │ EAS                       │ colorectal    │ II                 │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   1 │              1 │                810 │ false                 │ event        │
│ 1c86913ff5360133b733eea2b6ceedc3 │               68 │ female       │ AFR                       │ prostate      │ I                  │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ 1f2be3d276d3873dd5f99f0b01948057 │               63 │ female       │ AFR                       │ breast        │ IV                 │ NULL        │ NULL          │                  16 │                  1 │                   1 │                NULL │              1 │                270 │ true                  │ event        │
│ 1f50852f4863c71d79338df1d1927c36 │               40 │ female       │ AFR                       │ melanoma      │ II                 │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              1 │                720 │ true                  │ event        │
│ 2af4f9119b55b659835d5b51350d8cae │               69 │ male         │ SAS                       │ breast        │ III                │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              1 │               1260 │ false                 │ event        │
│ 2b286a480371bc0377fadb1df7087c4f │               46 │ male         │ AFR                       │ colorectal    │ III                │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ 2d7a55a6290cf979ec8f1199b3af52ce │               72 │ female       │ AFR                       │ colorectal    │ III                │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   1 │              1 │                450 │ true                  │ event        │
│ 3bc882a343cd766fb810a75f94608bb8 │               73 │ female       │ EAS                       │ head_and_neck │ IV                 │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              1 │                630 │ true                  │ event        │
│ 3e8e2cbedbfe621e8caac072c0a51400 │               75 │ male         │ EUR                       │ breast        │ I                  │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ 401b7d7f10e7bc2f60018e88f8555f40 │               71 │ female       │ AMR                       │ melanoma      │ I                  │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ 403531e4ddb9a406bc246e1190967772 │               76 │ male         │ AFR                       │ pancreatic    │ IV                 │ NULL        │ NULL          │                  16 │                  1 │                   1 │                NULL │              1 │                180 │ true                  │ event        │
│ 43c32ce2efa046465ab590642c6fc20d │               58 │ male         │ EAS                       │ colorectal    │ II                 │ NCT11111111 │ experimental  │                  16 │                  0 │                   0 │                   0 │              1 │               1350 │ false                 │ event        │
│                ·                 │                · │  ·           │  ·                        │   ·           │ ·                  │      ·      │      ·        │                   · │                  · │                   · │                   · │              · │                 ·  │   ·                   │   ·          │
│                ·                 │                · │  ·           │  ·                        │   ·           │ ·                  │      ·      │      ·        │                   · │                  · │                   · │                   · │              · │                 ·  │   ·                   │   ·          │
│                ·                 │                · │  ·           │  ·                        │   ·           │ ·                  │      ·      │      ·        │                   · │                  · │                   · │                   · │              · │                 ·  │   ·                   │   ·          │
│ 69c38b50360e78310af7a5d91f58cfea │               80 │ female       │ AFR                       │ renal         │ I                  │ NCT33333333 │ experimental  │                  16 │                  0 │                   0 │                   0 │              1 │                810 │ false                 │ event        │
│ 7cb24c47bee84ab3ca64faa110ea6013 │               60 │ male         │ AMR                       │ prostate      │ I                  │ NCT33333333 │ experimental  │                  16 │                  0 │                   1 │                   1 │              1 │                540 │ true                  │ event        │
│ 8742efe5106693e1322af4d097b672d3 │               77 │ female       │ EUR                       │ colorectal    │ I                  │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ 87ff756d6ac8e900d7d8ce63ec397258 │               72 │ male         │ SAS                       │ colorectal    │ III                │ NCT11111111 │ control       │                  16 │                  0 │                   1 │                   1 │              1 │                450 │ true                  │ event        │
│ 89227ccece1ad7f3583e4199172d8b40 │               53 │ female       │ EAS                       │ lung_nsclc    │ III                │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              1 │               1530 │ false                 │ event        │
│ 916046de783c8e1578724247ee9a5253 │               59 │ male         │ EUR                       │ colorectal    │ I                  │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ 98947a4e95ce6c105ba586c908411ddb │               64 │ female       │ EUR                       │ pancreatic    │ III                │ NCT33333333 │ control       │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ 9fdae958e7505915927a131eb4a82b30 │               49 │ female       │ EUR                       │ colorectal    │ IV                 │ NULL        │ NULL          │                  16 │                  1 │                   1 │                NULL │              1 │                270 │ true                  │ event        │
│ a05fd4c222e2041add20885fc322d766 │               63 │ male         │ EAS                       │ prostate      │ I                  │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ a50d2650c7ca8a48d1fdad3ff1e35225 │               46 │ female       │ EUR                       │ breast        │ II                 │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              1 │               1440 │ false                 │ event        │
│ b82f448f663362c8720ed8788ce50f58 │               57 │ male         │ EUR                       │ prostate      │ I                  │ NCT33333333 │ control       │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ c1d95da6ad8d0eac7b14e271676c7f07 │               68 │ male         │ AFR                       │ breast        │ IV                 │ NULL        │ NULL          │                  16 │                  0 │                   1 │                   1 │              1 │                360 │ true                  │ event        │
│ c78246c6be4d1464feeaed6862eb7b9d │               75 │ male         │ EAS                       │ colorectal    │ I                  │ NCT11111111 │ control       │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ cc3befeb488aa810a55bf81577ec9e04 │               46 │ female       │ EUR                       │ breast        │ III                │ NCT33333333 │ experimental  │                  16 │                  0 │                   0 │                   1 │              1 │                450 │ true                  │ event        │
│ d69181b6ad3045da4d8ead299e83c2ec │               54 │ female       │ EUR                       │ colorectal    │ I                  │ NCT11111111 │ experimental  │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ de7d8a2572ef9dad303f74e6ad0d5c99 │               80 │ female       │ EAS                       │ melanoma      │ I                  │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ e010cb25f79d6998c4417e19eb237ab4 │               71 │ female       │ SAS                       │ ovarian       │ III                │ NCT33333333 │ control       │                  16 │                  0 │                   0 │                   0 │              1 │                810 │ false                 │ event        │
│ ee59fa61036e1e99830e7b0279b761c4 │               44 │ male         │ SAS                       │ renal         │ IV                 │ NCT33333333 │ control       │                  16 │                  0 │                   0 │                   0 │              1 │                900 │ false                 │ event        │
│ f67af0c9fed2dfbc6280aaf0d932fff6 │               44 │ female       │ EAS                       │ breast        │ III                │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
│ fbd73ee745dc84247a116d37a0b5bb2a │               61 │ male         │ SAS                       │ renal         │ I                  │ NULL        │ NULL          │                  16 │                  0 │                   0 │                   0 │              0 │               NULL │ false                 │ censored     │
└──────────────────────────────────┴──────────────────┴──────────────┴───────────────────────────┴───────────────┴────────────────────┴─────────────┴───────────────┴─────────────────────┴────────────────────┴─────────────────────┴─────────────────────┴────────────────┴────────────────────┴───────────────────────┴──────────────┘
  48 rows (40 shown)                                                                                                                                     use .last to show entire result                                                                                                                                     16 columns
```

## q06_pharma_trial_landmark_by_arm
```
┌─────────────┬───────────────┬────────────┬────────────────────┬────────────┬──────────────┬──────────────┬───────────────────┬──────────────────┬─────────────────────┬─────────────────────────┬───────────────────────────┐
│  trial_id   │ treatment_arm │ tumor_type │ stage_at_diagnosis │ n_enrolled │ positive_d90 │ negative_d90 │ not_evaluable_d90 │ pct_positive_d90 │ recurred_within_2yr │ pct_recurred_within_2yr │ median_days_to_recurrence │
│   varchar   │    varchar    │  varchar   │      varchar       │   int64    │    int128    │    int128    │      int128       │      double      │       int128        │         double          │          double           │
├─────────────┼───────────────┼────────────┼────────────────────┼────────────┼──────────────┼──────────────┼───────────────────┼──────────────────┼─────────────────────┼─────────────────────────┼───────────────────────────┤
│ NCT11111111 │ control       │ colorectal │ I                  │          1 │            0 │            1 │                 0 │              0.0 │                   0 │                     0.0 │                      NULL │
│ NCT11111111 │ control       │ colorectal │ III                │          1 │            0 │            1 │                 0 │              0.0 │                   1 │                   100.0 │                     450.0 │
│ NCT11111111 │ experimental  │ colorectal │ I                  │          1 │            0 │            1 │                 0 │              0.0 │                   0 │                     0.0 │                      NULL │
│ NCT11111111 │ experimental  │ colorectal │ II                 │          1 │            0 │            1 │                 0 │              0.0 │                   0 │                     0.0 │                      NULL │
└─────────────┴───────────────┴────────────┴────────────────────┴────────────┴──────────────┴──────────────┴───────────────────┴──────────────────┴─────────────────────┴─────────────────────────┴───────────────────────────┘
```

## q07_clin_ops_pending_tests
```
┌────────────┬────────────┬──────────────────┬──────────────────┬──────────────────┐
│   bucket   │ n_patients │ oldest_test_date │ newest_test_date │ avg_days_pending │
│  varchar   │   int64    │       date       │       date       │      double      │
├────────────┼────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 31-60 days │          1 │ 2026-04-07       │ 2026-04-07       │             50.0 │
│ > 60 days  │          4 │ 2025-12-10       │ 2026-03-22       │            130.0 │
└────────────┴────────────┴──────────────────┴──────────────────┴──────────────────┘
```

## q08_patient_panel_detection_trajectory
```
┌─────────────────┬────────────────────┬────────────┬──────────┬────────────┬────────────┬──────────────────────┬──────────────────────┬────────────┬──────────────────┬───────────┬─────────────┐
│   gene_symbol   │    variant_key     │ chromosome │ position │ ref_allele │ alt_allele │ clinvar_significance │ test_sequence_number │ test_date  │ test_is_positive │ vaf_blood │ is_detected │
│     varchar     │      varchar       │  varchar   │  int64   │  varchar   │  varchar   │       varchar        │        int32         │    date    │     boolean      │  double   │   boolean   │
├─────────────────┼────────────────────┼────────────┼──────────┼────────────┼────────────┼──────────────────────┼──────────────────────┼────────────┼──────────────────┼───────────┼─────────────┤
│ APOL3           │ chr22_36144569_T_G │ chr22      │ 36144569 │ T          │ G          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ CRYBB2P1        │ chr22_25518760_C_G │ chr22      │ 25518760 │ C          │ G          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ DENND6B         │ chr22_50321053_G_A │ chr22      │ 50321053 │ G          │ A          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ EFCAB6          │ chr22_43620385_C_T │ chr22      │ 43620385 │ C          │ T          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ ENSG00000290950 │ chr22_20357667_C_T │ chr22      │ 20357667 │ C          │ T          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ GTPBP1          │ chr22_38714119_G_A │ chr22      │ 38714119 │ G          │ A          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ HMGXB4          │ chr22_35288066_C_T │ chr22      │ 35288066 │ C          │ T          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ KREMEN1         │ chr22_29120429_G_A │ chr22      │ 29120429 │ G          │ A          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ MYO18B          │ chr22_25807885_C_T │ chr22      │ 25807885 │ C          │ T          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ POTEH           │ chr22_15711078_G_C │ chr22      │ 15711078 │ G          │ C          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ PRAMENP         │ chr22_22019090_C_A │ chr22      │ 22019090 │ C          │ A          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ SYN3            │ chr22_32987434_G_A │ chr22      │ 32987434 │ G          │ A          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ NULL            │ chr22_11575408_C_G │ chr22      │ 11575408 │ C          │ G          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ NULL            │ chr22_15532310_T_C │ chr22      │ 15532310 │ T          │ C          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ NULL            │ chr22_41067300_G_A │ chr22      │ 41067300 │ G          │ A          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ NULL            │ chr22_46571720_G_A │ chr22      │ 46571720 │ G          │ A          │ NULL                 │                   18 │ 2023-12-04 │ false            │       0.0 │ false       │
│ APOL3           │ chr22_36144569_T_G │ chr22      │ 36144569 │ T          │ G          │ NULL                 │                   19 │ 2024-03-03 │ false            │       0.0 │ false       │
│ CRYBB2P1        │ chr22_25518760_C_G │ chr22      │ 25518760 │ C          │ G          │ NULL                 │                   19 │ 2024-03-03 │ false            │       0.0 │ false       │
│ DENND6B         │ chr22_50321053_G_A │ chr22      │ 50321053 │ G          │ A          │ NULL                 │                   19 │ 2024-03-03 │ false            │       0.0 │ false       │
│ EFCAB6          │ chr22_43620385_C_T │ chr22      │ 43620385 │ C          │ T          │ NULL                 │                   19 │ 2024-03-03 │ false            │       0.0 │ false       │
│  ·              │         ·          │   ·        │     ·    │ ·          │ ·          │  ·                   │                    · │     ·      │   ·              │        ·  │   ·         │
│  ·              │         ·          │   ·        │     ·    │ ·          │ ·          │  ·                   │                    · │     ·      │   ·              │        ·  │   ·         │
│  ·              │         ·          │   ·        │     ·    │ ·          │ ·          │  ·                   │                    · │     ·      │   ·              │        ·  │   ·         │
│ NULL            │ chr22_11575408_C_G │ chr22      │ 11575408 │ C          │ G          │ NULL                 │                   19 │ 2024-03-03 │ false            │       0.0 │ false       │
│ NULL            │ chr22_15532310_T_C │ chr22      │ 15532310 │ T          │ C          │ NULL                 │                   19 │ 2024-03-03 │ false            │       0.0 │ false       │
│ NULL            │ chr22_41067300_G_A │ chr22      │ 41067300 │ G          │ A          │ NULL                 │                   19 │ 2024-03-03 │ false            │       0.0 │ false       │
│ NULL            │ chr22_46571720_G_A │ chr22      │ 46571720 │ G          │ A          │ NULL                 │                   19 │ 2024-03-03 │ false            │       0.0 │ false       │
│ APOL3           │ chr22_36144569_T_G │ chr22      │ 36144569 │ T          │ G          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ CRYBB2P1        │ chr22_25518760_C_G │ chr22      │ 25518760 │ C          │ G          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ DENND6B         │ chr22_50321053_G_A │ chr22      │ 50321053 │ G          │ A          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ EFCAB6          │ chr22_43620385_C_T │ chr22      │ 43620385 │ C          │ T          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ ENSG00000290950 │ chr22_20357667_C_T │ chr22      │ 20357667 │ C          │ T          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ GTPBP1          │ chr22_38714119_G_A │ chr22      │ 38714119 │ G          │ A          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ HMGXB4          │ chr22_35288066_C_T │ chr22      │ 35288066 │ C          │ T          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ KREMEN1         │ chr22_29120429_G_A │ chr22      │ 29120429 │ G          │ A          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ MYO18B          │ chr22_25807885_C_T │ chr22      │ 25807885 │ C          │ T          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ POTEH           │ chr22_15711078_G_C │ chr22      │ 15711078 │ G          │ C          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ PRAMENP         │ chr22_22019090_C_A │ chr22      │ 22019090 │ C          │ A          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ SYN3            │ chr22_32987434_G_A │ chr22      │ 32987434 │ G          │ A          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ NULL            │ chr22_11575408_C_G │ chr22      │ 11575408 │ C          │ G          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ NULL            │ chr22_15532310_T_C │ chr22      │ 15532310 │ T          │ C          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ NULL            │ chr22_41067300_G_A │ chr22      │ 41067300 │ G          │ A          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
│ NULL            │ chr22_46571720_G_A │ chr22      │ 46571720 │ G          │ A          │ NULL                 │                   20 │ 2024-06-01 │ false            │       0.0 │ false       │
└─────────────────┴────────────────────┴────────────┴──────────┴────────────┴────────────┴──────────────────────┴──────────────────────┴────────────┴──────────────────┴───────────┴─────────────┘
  48 rows (40 shown)                                                                 use .last to show entire result                                                                  12 columns
```

## q09_cumulative_incidence_by_stage
```
┌────────────────────┬───────────────┬─────────────────┬───────────────────┬─────────────────────┬────────────────┬────────────────────────────────┬─────────────────────────┐
│ stage_at_diagnosis │ landmark_days │ landmark_months │ cumulative_events │ at_risk_at_landmark │ total_in_stage │ crude_cumulative_incidence_pct │ pct_at_risk_at_landmark │
│      varchar       │     int32     │     double      │       int64       │        int64        │     int64      │             double             │         double          │
├────────────────────┼───────────────┼─────────────────┼───────────────────┼─────────────────────┼────────────────┼────────────────────────────────┼─────────────────────────┤
│ I                  │            90 │             3.0 │                 0 │                  17 │             17 │                            0.0 │                   100.0 │
│ I                  │           180 │             6.0 │                 0 │                  17 │             17 │                            0.0 │                   100.0 │
│ I                  │           365 │            12.2 │                 0 │                  17 │             17 │                            0.0 │                   100.0 │
│ I                  │           540 │            18.0 │                 1 │                  17 │             17 │                            5.9 │                   100.0 │
│ I                  │           730 │            24.3 │                 1 │                  16 │             17 │                            5.9 │                    94.1 │
│ I                  │          1095 │            36.5 │                 2 │                  15 │             17 │                           11.8 │                    88.2 │
│ II                 │            90 │             3.0 │                 0 │                   9 │              9 │                            0.0 │                   100.0 │
│ II                 │           180 │             6.0 │                 0 │                   9 │              9 │                            0.0 │                   100.0 │
│ II                 │           365 │            12.2 │                 0 │                   9 │              9 │                            0.0 │                   100.0 │
│ II                 │           540 │            18.0 │                 0 │                   9 │              9 │                            0.0 │                   100.0 │
│ II                 │           730 │            24.3 │                 1 │                   8 │              9 │                           11.1 │                    88.9 │
│ II                 │          1095 │            36.5 │                 2 │                   7 │              9 │                           22.2 │                    77.8 │
│ III                │            90 │             3.0 │                 0 │                  13 │             13 │                            0.0 │                   100.0 │
│ III                │           180 │             6.0 │                 0 │                  13 │             13 │                            0.0 │                   100.0 │
│ III                │           365 │            12.2 │                 0 │                  13 │             13 │                            0.0 │                   100.0 │
│ III                │           540 │            18.0 │                 3 │                  10 │             13 │                           23.1 │                    76.9 │
│ III                │           730 │            24.3 │                 5 │                   8 │             13 │                           38.5 │                    61.5 │
│ III                │          1095 │            36.5 │                 7 │                   6 │             13 │                           53.8 │                    46.2 │
│ IV                 │            90 │             3.0 │                 0 │                  11 │             11 │                            0.0 │                   100.0 │
│ IV                 │           180 │             6.0 │                 2 │                  11 │             11 │                           18.2 │                   100.0 │
│ IV                 │           365 │            12.2 │                 6 │                   5 │             11 │                           54.5 │                    45.5 │
│ IV                 │           540 │            18.0 │                 7 │                   5 │             11 │                           63.6 │                    45.5 │
│ IV                 │           730 │            24.3 │                 9 │                   2 │             11 │                           81.8 │                    18.2 │
│ IV                 │          1095 │            36.5 │                11 │                   0 │             11 │                          100.0 │                     0.0 │
└────────────────────┴───────────────┴─────────────────┴───────────────────┴─────────────────────┴────────────────┴────────────────────────────────┴─────────────────────────┘
  24 rows                                                                                                                                                          8 columns
```

## q10_serial_testing_compliance
```
┌───────────────┬────────────────────┬─────────────────────┬─────────────┬───────────────┬───────────────────────┬──────────────────────────┬───────────┬───────────┐
│  tumor_type   │ stage_at_diagnosis │ n_eligible_patients │ n_compliant │ pct_compliant │ avg_tests_per_patient │ median_tests_per_patient │ min_tests │ max_tests │
│    varchar    │      varchar       │        int64        │   int128    │    double     │        double         │          double          │   int64   │   int64   │
├───────────────┼────────────────────┼─────────────────────┼─────────────┼───────────────┼───────────────────────┼──────────────────────────┼───────────┼───────────┤
│ bladder       │ II                 │                   1 │           1 │         100.0 │                  20.0 │                     20.0 │        20 │        20 │
│ breast        │ I                  │                   1 │           1 │         100.0 │                  20.0 │                     20.0 │        20 │        20 │
│ breast        │ II                 │                   2 │           2 │         100.0 │                  18.0 │                     18.0 │        16 │        20 │
│ breast        │ III                │                   3 │           3 │         100.0 │                  13.0 │                     14.0 │         5 │        20 │
│ breast        │ IV                 │                   2 │           2 │         100.0 │                   6.5 │                      6.5 │         4 │         9 │
│ colorectal    │ I                  │                   5 │           5 │         100.0 │                  20.0 │                     20.0 │        20 │        20 │
│ colorectal    │ II                 │                   4 │           4 │         100.0 │                  14.5 │                     14.5 │         9 │        20 │
│ colorectal    │ III                │                   4 │           4 │         100.0 │                  11.0 │                      9.5 │         5 │        20 │
│ colorectal    │ IV                 │                   1 │           1 │         100.0 │                   8.0 │                      8.0 │         8 │         8 │
│ head_and_neck │ III                │                   1 │           1 │         100.0 │                   8.0 │                      8.0 │         8 │         8 │
│ head_and_neck │ IV                 │                   1 │           1 │         100.0 │                   7.0 │                      7.0 │         7 │         7 │
│ lung_nsclc    │ I                  │                   1 │           1 │         100.0 │                  20.0 │                     20.0 │        20 │        20 │
│ lung_nsclc    │ II                 │                   1 │           1 │         100.0 │                  18.0 │                     18.0 │        18 │        18 │
│ lung_nsclc    │ III                │                   2 │           2 │         100.0 │                  14.5 │                     14.5 │        12 │        17 │
│ melanoma      │ I                  │                   3 │           3 │         100.0 │                  20.0 │                     20.0 │        20 │        20 │
│ melanoma      │ II                 │                   1 │           1 │         100.0 │                   8.0 │                      8.0 │         8 │         8 │
│ ovarian       │ III                │                   1 │           1 │         100.0 │                   9.0 │                      9.0 │         9 │         9 │
│ pancreatic    │ III                │                   1 │           1 │         100.0 │                  20.0 │                     20.0 │        20 │        20 │
│ pancreatic    │ IV                 │                   1 │           1 │         100.0 │                   6.0 │                      6.0 │         6 │         6 │
│ prostate      │ I                  │                   5 │           5 │         100.0 │                  17.2 │                     20.0 │         6 │        20 │
│ prostate      │ III                │                   1 │           1 │         100.0 │                   7.0 │                      7.0 │         7 │         7 │
│ renal         │ I                  │                   2 │           2 │         100.0 │                  14.5 │                     14.5 │         9 │        20 │
│ renal         │ IV                 │                   1 │           1 │         100.0 │                  10.0 │                     10.0 │        10 │        10 │
└───────────────┴────────────────────┴─────────────────────┴─────────────┴───────────────┴───────────────────────┴──────────────────────────┴───────────┴───────────┘
  23 rows                                                                                                                                                 9 columns
```

