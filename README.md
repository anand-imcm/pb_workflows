# pb_workflows


Notes related to the [SMRT-LINK](https://www.pacb.com/support/software-downloads/) command line suite.

The contents within the [`pipelines`](pipelines/) directory of this repo are obtained from the `pbpipeline-resources` within the SMRT-LINK package.


## Download and extract the SMRT-LINK command line installer


```bash
wget https://downloads.pacbcloud.com/public/software/installers/smrtlink_12.0.0.177059.zip

unzip smrtlink_12.0.0.177059.zip
```

## SMRT Tools-only installation


```bash
./smrtlink_12.0.0.177059.run --rootdir ~/smrtlink-12.0.0 --smrttools-only
```

The wdl scripts from the SMRTLINK package are deposited in this github repository.


# Using the `pbcromwell` tool


## List all the available workflows


```bash
~/smrtlink-12.0.0/smrtcmds/bin/pbcromwell show-workflows
```


Output:

```
cromwell.workflows.pb_detect_methyl: 5mC CpG Detection
cromwell.workflows.pb_ccs: Circular Consensus Sequencing (CCS)
cromwell.workflows.pb_demux_ccs: Demultiplex Barcodes
cromwell.workflows.pb_export_ccs: Export Reads
cromwell.workflows.pb_assembly_hifi: Genome Assembly
cromwell.workflows.pb_align_ccs: HiFi Mapping
cromwell.workflows.pb_sars_cov2_kit: HiFiViral SARS-CoV-2 Analysis
cromwell.workflows.pb_isoseq3: Iso-Seq Analysis
cromwell.workflows.pb_mark_duplicates: Mark PCR Duplicates
cromwell.workflows.pb_microbial_analysis: Microbial Genome Analysis
cromwell.workflows.pb_segment_reads: Read Segmentation
cromwell.workflows.pb_segment_reads_and_sc_isoseq: Read Segmentation and Single-Cell Iso-Seq
cromwell.workflows.pb_sc_isoseq: Single-Cell Iso-Seq
cromwell.workflows.pb_sv_ccs: Structural Variant Calling
cromwell.workflows.pb_trim_adapters: Trim Ultra-Low Adapters
cromwell.workflows.pb_undo_demux: Undo Demultiplexing
cromwell.workflows.pb_variant_calling: Variant Calling

Run 'pbcromwell show-workflow-details <ID>' to display further
information about a workflow.  Note that the cromwell.workflows.
prefix is optional.

The full SMRT Tools documentation for this command and PacBio
analysis workflows is available online:
https://www.pacb.com/support/documentation

```


## Get the usage instructions for a particular workflow

Example: 
Opting for the `pb_variant_calling` workflow from the above list of available workflows.


```bash
~/smrtlink-12.0.0/smrtcmds/bin/pbcromwell show-workflow-details pb_variant_calling
```

Output:

```

Workflow Summary
Workflow Id    : cromwell.workflows.pb_variant_calling
Name           : Variant Calling
Description    : Cromwell workflow pb_variant_calling
Required Inputs: ConsensusReadSet XML, ReferenceSet XML
Tags           : deepvariant, ccs, auto-analysis, cromwell, analysis 
Task Options:
  filter_min_qv = 20
    Min. CCS Predicted Accuracy (Phred Scale) (integer)
  mapping_biosample_name = 
    Bio Sample Name of Aligned Dataset (string)
  mapping_pbmm2_overrides = 
    Advanced pbmm2 Options (string)
  mapping_max_nchunks = 4
    Mapping max nchunks (integer)
  pbsv_chunk_length = 1M
    Pbsv chunk length (string)
  min_sv_length = 20
    Minimum Length of Structural Variant (bp) (integer)
  pbsv_override_args = 
    Advanced pbsv Options (string)
  min_percent_reads = 10
    Minimum % of Reads that Support Variant (any one sample) (integer)
  min_reads_one_sample = 3
    Minimum Reads that Support Variant (any one sample) (integer)
  min_reads_all_samples = 3
    Minimum Reads that Support Variant (total over all samples) (integer)
  min_reads_per_strand_all_samples = 0
    Min reads per strand all samples (integer)
  deepvariant_docker_image = google/deepvariant:1.5.0
    Docker Image for DeepVariant (string)
  enable_gpu = False
    Use GPU if available (boolean)
  whatshap_docker_image = quay.io/biocontainers/whatshap:1.4--py39hc16433a_1
    Docker Image for WhatsHap (string)
  add_memory_mb = 0
    Add task memory (MB) (integer)


Example Usage:

  $ pbcromwell run pb_variant_calling \
      -e input1.consensusreadset.xml \
      -e input2.referenceset.xml \

  $ pbcromwell run pb_variant_calling \
      -e input1.consensusreadset.xml \
      -e input2.referenceset.xml \
      --task-option filter_min_qv=20 \
      --task-option mapping_biosample_name="" \
      --task-option mapping_pbmm2_overrides="" \
      --task-option mapping_max_nchunks=4 \
      --task-option pbsv_chunk_length="1M" \
      --task-option min_sv_length=20 \
      --task-option pbsv_override_args="" \
      --task-option min_percent_reads=10 \
      --task-option min_reads_one_sample=3 \
      --task-option min_reads_all_samples=3 \
      --task-option min_reads_per_strand_all_samples=0 \
      --task-option deepvariant_docker_image="google/deepvariant:1.5.0" \
      --task-option enable_gpu=False \
      --task-option whatshap_docker_image="quay.io/biocontainers/whatshap:1.4--py39hc16433a_1" \
      --task-option add_memory_mb=0 \
      --config cromwell.conf \
      --nproc 8

The full SMRT Tools documentation for this command and PacBio
analysis workflows is available online:
https://www.pacb.com/support/documentation

```
