# pb_workflows

Notes related to the [SMRT-LINK](https://www.pacb.com/support/software-downloads/) command line suite


## Download and extract the SMRT-LINK command line installer

```bash
wget https://downloads.pacbcloud.com/public/software/installers/smrtlink_12.0.0.177059.zip

unzip smrtlink_12.0.0.177059.zip
```

## SMRT Tools-only installation

```bash
./smrtlink_12.0.0.177059.run --rootdir ~/smrtlink-12.0.0 --smrttools-only
```

## extract the WDL workflows from the SMRT-LINK package

```bash
unzip ~/smrtlink-12.0.0/./install/smrtlink-release_12.0.0.177059/bundles/smrttools/install/smrttools-release_12.0.0.177059/private/pacbio/pbpipeline-resources/wdl.zip -d ~/smrtlink-12.0.0/pb_workflows
```


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