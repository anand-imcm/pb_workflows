# Molecular loop SARS-CoV-2 variant calling pipeline.

version 1.0

# To avoid any confusion over DataSet XML filters this workflow is very strict
# about splitting the input dataset by BAM file, each of which is assumed to
# represent a single sample (as output by the pb_demux_* workflows).  The
# output will be a series of chunk XMLs, which will include a barcode quality
# filter if the BAMs contain barcoding annotations (the standard use case).
# We also need to collect FASTA files for tools that don't read our XML.
# (The barcodes are fine as is but since we need to resolve the absolute path
# of the FASTA file this is handled here as well.)
task collect_inputs {
  input {
    File eid_ccs
    File eid_ref_dataset
    # this is not actually read
    File? sample_wells_csv
    Int min_bq = 80
    File? plate

    Int nproc = 1
    String log_level = "INFO"
    File? tmp_dir
  }
  Boolean write_plateqc_template = !defined(sample_wells_csv)
  command {
    python3 -m pbcoretools.tasks.sars_cov2_kit_inputs \
      --log-level DEBUG \
      --min-bq ${min_bq} \
      ${true="--write-plateqc-template" false="" write_plateqc_template} \
      ${eid_ccs} ${eid_ref_dataset}
  }
  runtime {
    cpu: 1
    memory: "8GB"
  }
  output {
    Array[File] chunks = glob("chunk.*.consensusreadset.xml")
    File genome_fasta = "genome.fasta"
    File genome_fasta_fai = "genome.fasta.fai"
    File? sample_wells_csv_template = "sample_wells_plateqc.csv"
  }
}

# This task is run in parallel over sample BAMs.  Because there are many
# ways for a sample to fail (including but not limited to sample contamination,
# poor coverage, or bugs), the command script is more fault-tolerant than
# usual.
task run_sample {
  input {
    File ccs_reads
    File genome_fasta
    File genome_fasta_fai
    File? mimux_probe_seq_fasta
    Float min_alt_freq = 0.5
    Int min_coverage = 2
    Int min_bq = 80
    String mimux_overrides = ""

    Int nproc = 4
    String log_level = "INFO"
    File? tmp_dir
  }

  # These are constants
  Int min_score_lead = 10
  Int min_cluster_read_count = 2
  Int min_amplicon_length = 100

  # These are the bcftools variant calling parameters, tested by John Harting.
  Float bcftools_gap_open_prob = 25
  Float bcftools_ext_prob = 1
  Float bcftools_gap_fraction = 0.01
  Int bcftools_max_depth = 1000
  # John Harting did testing at 450 across another of samples
  Int bcftools_max_indel_size = 450
  Int bcftools_max_indel_depth = 5000
  Int bcftools_min_indel_reads = 3
  Int bcftools_haplotype = 500
  Int bcftools_seed = 1984
  # Quality for consensus tool
  Int min_vcfcons_qual = 60

  # FIXME cdunn pointed out that the tests for empty or non-existent output
  # files is too tightly coupled to tool behavior and we should solve this
  # with traps instead.  it's not clear what we can do in a Cromwell script
  # but there is room for improvement here
  command {
    set -e
    set -x
    echo `pwd`

    # to remove any ambiguity we generate a new BAM file first; this will
    # have already been filtered by BQ >= 80
    dataset \
      --log-level DEBUG \
      --log-file dataset_consolidate.log \
      consolidate \
      ${ccs_reads} \
      input.ccs.bam input.consensusreadset.xml

    # the input BAM will be used to set the sample name in the gathered outputs
    echo `pwd`/input.ccs.bam > outputs.fofn

    # FIXME VCFCons can't read the biosample info directly, and it's also
    # insensitive to spaces in the sample name, hence the "clean" txt.  We
    # preserve the spaces in all reporting, just not the consensus outputs.
    python3 <<EOF
    from pbcore.io import BamReader
    bam = BamReader("input.ccs.bam")
    biosample = bam.readGroupTable[0].SampleName.strip()
    with open("biosample_clean.txt", "wt") as txt_out:
      txt_out.write(biosample.replace(" ", "_"))
    with open("biosample.txt", "wt") as txt_out:
      txt_out.write(biosample)
    EOF

    ln -s ${genome_fasta} genome.fasta
    ln -s ${genome_fasta_fai} genome.fasta.fai

    # remove and record arms & UMI sequences
    mimux \
      --log-level ${log_level} \
      --log-file preprocessing.log \
      --num-threads ${nproc} \
      ${"--probes " + mimux_probe_seq_fasta} \
      --probe-report output.probe_counts.tsv \
      ${mimux_overrides} \
      input.consensusreadset.xml \
      mimux_trimmed.bam

    if [ -s "mimux_trimmed.bam" ]; then
      echo `pwd`/output.probe_counts.tsv >> outputs.fofn
      # index for bam2fasq -- requires a *.pbi
      pbindex mimux_trimmed.bam

      # Generate fastq
      bam2fastq -u -o output.hifi_reads mimux_trimmed.bam
      echo `pwd`/output.hifi_reads.fastq >> outputs.fofn

      # Map the primer-UMI-arm-trimmed MIP reads to the reference genome
      pbmm2 align \
        -j ${nproc} \
        --log-level ${log_level} \
        --log-file mapped_trimmed.log \
        --sort --preset HIFI \
        genome.fasta mimux_trimmed.bam output.mapped.bam
      pbindex output.mapped.bam
      echo `pwd`/output.mapped.bam >> outputs.fofn

      # Get coverage metrics from samtools
      samtools mpileup \
        --min-BQ 1 \
        -f genome.fasta \
        -s output.mapped.bam > mapped.bam.mpileup
      samtools depth \
        -q 0 -Q 0 \
        output.mapped.bam > mapped.bam.depth
    else
      echo "ERROR: samtools depth failed, no reads?"
    fi

    if [ -s "output.mapped.bam" ]; then
    (bcftools mpileup --open-prob ${bcftools_gap_open_prob} \
                --indel-size ${bcftools_max_indel_size} \
                --gap-frac ${bcftools_gap_fraction} \
                --ext-prob ${bcftools_ext_prob} \
                --min-ireads ${bcftools_min_indel_reads} \
                --max-depth ${bcftools_max_depth} \
                --max-idepth ${bcftools_max_indel_depth} \
                --seed ${bcftools_seed} \
                -h ${bcftools_haplotype} \
                -B \
                -a FORMAT/AD \
                -f genome.fasta \
                output.mapped.bam | \
      bcftools call -mv -Ov | \
      bcftools norm -f genome.fasta - | \
      bcftools filter -e 'QUAL < 20' - > variants_bcftools.vcf) || \
      echo "ERROR: variant calling failed"

      (VCFCons \
        genome.fasta sample \
        --sample-name "`cat biosample_clean.txt`" \
        --min_coverage ${min_coverage} \
        --min_alt_freq ${min_alt_freq} \
        --vcf_type bcftools \
        --input_depth mapped.bam.depth \
        --min_qual ${min_vcfcons_qual} \
        --input_vcf variants_bcftools.vcf > vcfcons.log ) || \
        echo "ERROR: vcfcons failed"
    fi

    if [ -s "sample.vcfcons.info.csv" ]; then
      ln -s sample.vcfcons.vcf output.vcf
      ln -s sample.vcfcons.fasta output.consensus.fasta

      # Now map the consensus sequences to the reference genome
      pbmm2 align \
        -j ${nproc} \
        --log-level ${log_level} \
        --log-file pbmm2_vcfcons_frag_aligned.log \
        --sort --preset HIFI \
        genome.fasta sample.vcfcons.frag.fasta \
        output.consensus_mapped.bam

      # this report essentially just annotates the existing outputs with the
      # sample name pulled from the CCS BAM header.  Inputs are the info.csv
      # and variants.csv from VCFCons.  Outputs are a report.json
      # (corresponding to the info.csv) and variants CSV file.
      python3 -m pbreports.report.sars_cov2_kit_sample \
        --log-level ${log_level} \
        --log-file pbreports_sars_cov2_sample.log \
        --min-coverage ${min_coverage} \
        input.ccs.bam \
        --mapped output.mapped.bam \
        --genome genome.fasta \
        --trimmed mimux_trimmed.bam \
        --summary-csv sample.vcfcons.info.csv \
        --variants-tsv sample.vcfcons.variants.csv \
        --multistrain-csv sample.multistrain.info.csv \
        --report-out sample_variants.report.json \
        --variants-out sample_variants.csv

      # collect VCFCons outputs
      ln -s variants_bcftools.vcf output.raw.vcf
      echo `pwd`/output.raw.vcf >> outputs.fofn
      echo `pwd`/output.vcf >> outputs.fofn
      echo `pwd`/output.consensus.fasta >> outputs.fofn
      echo `pwd`/output.consensus_mapped.bam >> outputs.fofn
      echo `pwd`/output.coverage.png >> outputs.fofn
    else
      echo "biosample,path" > FAILED
      echo "`cat biosample.txt`,`pwd`" >> FAILED
    fi
  }
  runtime {
    cpu: nproc
    memory: "4GB"
  }
  output {
    File outputs_fofn = "outputs.fofn"
    # These may not exist if one of the steps failed
    File? report = "sample_variants.report.json"
    File? coverage_gff = "output.coverage.gff"
    File? variants = "sample_variants.csv"
    File? failure = "FAILED"
  }
}

task pbreports_sars_cov2_kit_summary {
  input {
    Array[File] sample_reports
    Array[File] sample_variants
    Array[File] coverage_gffs
    File genome_fasta
    File? sample_wells_csv
    File? sample_failures_csv

    Int nproc = 1
    String log_level = "INFO"
    File? tmp_dir
  }
  command {
    set -e

    # collect per-sample report JSON to make a table
    python3 -m pbcoretools.tasks.gather \
      --log-level ${log_level} \
      merged_samples.report.json \
      ${sep=" " sample_reports}

    # collect per-sample variants
    python3 -m pbcoretools.tasks.gather \
      --log-level ${log_level} \
      all.vcfcons.variants.csv \
      ${sep=" " sample_variants}

    python3 -m pbreports.tasks.plot_combined_coverage \
      --log-level ${log_level} \
      -o all_samples_coverage.png \
      ${genome_fasta} \
      ${sep=" " coverage_gffs}

    # generate the summary report
    python3 -m pbreports.report.sars_cov2_kit_summary \
      --log-level ${log_level} \
      --coverage-png all_samples_coverage.png \
      ${"--sample-wells-csv " + sample_wells_csv} \
      ${"--sample-failures-csv " + sample_failures_csv} \
      --csv-out sample_summary.csv \
      merged_samples.report.json \
      summary.report.json
  }
  runtime {
    cpu: 1
    memory: "2GB"
  }
  output {
    File report = "summary.report.json"
    File variants_csv = "all.vcfcons.variants.csv"
    File summary_csv = "sample_summary.csv"
  }
}

task collect_failures {
  input {
    Array[File] failures

    Int nproc = 1
    String log_level = "INFO"
    File? tmp_dir
  }
  command {
    python3 -m pbcoretools.tasks.gather \
      --log-level ${log_level} \
      sample_failures.csv \
      ${sep=" " failures}
  }
  runtime {
    cpu: 1
    memory: "200MB"
  }
  output {
    File failures_csv = "sample_failures.csv"
  }
}

task collect_outputs {
  input {
    Array[File] outputs_fofns
    File? sample_failures_csv

    Int nproc = 1
    String log_level = "INFO"
    File? tmp_dir
  }
  String input_prefix = "output"
  String output_prefix = "samples"
  command {
    set -e

    # outputs are optional if all samples fail
    touch ${output_prefix}.mapped.bam.zip
    touch ${output_prefix}.probe_counts.tsv.zip
    touch ${output_prefix}.vcf.zip
    touch ${output_prefix}.raw.vcf.zip
    touch ${output_prefix}.consensus.fasta.zip
    touch ${output_prefix}.consensus_mapped.bam.zip
    touch ${output_prefix}.hifi_reads.fastq.zip
    touch ${output_prefix}.coverage.png.zip

    python3 -m pbcoretools.tasks.sars_cov2_outputs \
      --log-level ${log_level} \
      --input-prefix ${input_prefix} \
      --output-prefix ${output_prefix} \
      ${"--failures " + sample_failures_csv } \
      ${sep=" " outputs_fofns}

    # this is an optimization for Cromwell call caching - it's simpler to
    # declare the zip files as output File objects, but by just reading the
    # name we bypass blocking I/O on large runs
    echo `pwd`/${output_prefix}.mapped.bam.zip > mapped_zip.fofn
    echo `pwd`/${output_prefix}.probe_counts.tsv.zip > probe_counts_zip.fofn
    echo `pwd`/${output_prefix}.vcf.zip > vcf_zip.fofn
    echo `pwd`/${output_prefix}.raw.vcf.zip > raw_vcf_zip.fofn
    echo `pwd`/${output_prefix}.consensus.fasta.zip > fasta_zip.fofn
    echo `pwd`/${output_prefix}.consensus_mapped.bam.zip > aligned_frag_zip.fofn
    echo `pwd`/${output_prefix}.hifi_reads.fastq.zip > trimmed_zip.fofn
    echo `pwd`/${output_prefix}.coverage.png.zip > coverage_png_zip.fofn
  }
  Int total_mem_mb = nproc * 100
  runtime {
    cpu: nproc
    memory: "${total_mem_mb}MB"
  }
  output {
    String vcf_zip_fn = read_string("vcf_zip.fofn")
    String raw_vcf_zip_fn = read_string("raw_vcf_zip.fofn")
    String fasta_zip_fn = read_string("fasta_zip.fofn")
    String mapped_zip_fn = read_string("mapped_zip.fofn")
    String aligned_frag_zip_fn = read_string("aligned_frag_zip.fofn")
    String trimmed_zip_fn = read_string("trimmed_zip.fofn")
    String coverage_png_zip_fn = read_string("coverage_png_zip.fofn")
    String probe_counts_zip_fn = read_string("probe_counts_zip.fofn")
    #String lima_summary_zip_fn = read_string("lima_summary_zip.fofn")
    # this should be relatively small
    File? errors_zip = "error_logs.zip"
  }
}

workflow pb_sars_cov2_kit {
  input {
    File eid_ccs
    # genome
    File eid_ref_dataset
    # optional probe sequences
    File? probes_fasta
    Int min_coverage = 4
    Float min_alt_freq = 0.5
    Int min_bq = 80
    String mimux_overrides = ""
    File? sample_wells_csv

    Int nproc = 4
    String log_level = "INFO"
    File? tmp_dir
    # this is not actually respected
    Int max_nchunks = 1
  }

  Int NPROC_MAX = 4
  Int nproc_sample = if (nproc > NPROC_MAX) then NPROC_MAX else nproc

  call collect_inputs {
    input:
      eid_ccs = eid_ccs,
      eid_ref_dataset = eid_ref_dataset,
      sample_wells_csv = sample_wells_csv,
      min_bq = min_bq,
      log_level = log_level
  }

  scatter (barcoded_ds in collect_inputs.chunks) {
    call run_sample {
      input:
        ccs_reads = barcoded_ds,
        mimux_probe_seq_fasta = probes_fasta,
        genome_fasta = collect_inputs.genome_fasta,
        genome_fasta_fai = collect_inputs.genome_fasta_fai,
        min_coverage = min_coverage,
        min_alt_freq = min_alt_freq,
        min_bq = min_bq,
        mimux_overrides = mimux_overrides,
        log_level = log_level,
        nproc = nproc_sample
    }
  }

  # If there are one ore more FAILED sentinel files, gather them as CSV for
  # download and reporting
  Array[File] failures = select_all(run_sample.failure)
  if (length(failures) > 0) {
    call collect_failures {
      input:
        failures = failures,
        log_level = log_level
    }
  }

  # Only run the report if at least one sample succeeded
  Array[File] sample_reports = select_all(run_sample.report)
  if (length(sample_reports) > 0) {
    call pbreports_sars_cov2_kit_summary {
      input:
        sample_reports = sample_reports,
        sample_variants = select_all(run_sample.variants),
        sample_failures_csv = collect_failures.failures_csv,
        coverage_gffs = select_all(run_sample.coverage_gff),
        genome_fasta = collect_inputs.genome_fasta,
        sample_wells_csv = sample_wells_csv,
        log_level = log_level
    }
  }

  call collect_outputs {
    input:
      outputs_fofns = run_sample.outputs_fofn,
      sample_failures_csv = collect_failures.failures_csv,
      nproc = nproc,
      log_level = log_level
  }

  output {
    File? report_sars_cov2 = pbreports_sars_cov2_kit_summary.report
    File? summary_csv = pbreports_sars_cov2_kit_summary.summary_csv
    # to SMRT Link these will just look like any other path.  note that they
    # may be completely empty files, but they will still be created
    String vcf_zip = collect_outputs.vcf_zip_fn
    String raw_vcf_zip = collect_outputs.raw_vcf_zip_fn
    String fasta_zip = collect_outputs.fasta_zip_fn
    String mapped_zip = collect_outputs.mapped_zip_fn
    String aligned_frag_zip = collect_outputs.aligned_frag_zip_fn
    String trimmed_zip = collect_outputs.trimmed_zip_fn
    String coverage_png_zip = collect_outputs.coverage_png_zip_fn
    String probe_counts_zip = collect_outputs.probe_counts_zip_fn
    File? sample_failures_csv = collect_failures.failures_csv
    File? errors_zip = collect_outputs.errors_zip
    File? sample_wells_csv_template = collect_inputs.sample_wells_csv_template
  }
}
