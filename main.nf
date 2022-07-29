#!/usr/bin/env nextflow
/*
=========================================================================================
  		NANOME(Nanopore methylation) pipeline for Oxford Nanopore sequencing
=========================================================================================
 NANOME Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/LabShengLi/nanome
 @Author   : Yang Liu
 @FileName : main.nf
 @Software : NANOME project
 @Organization : JAX Li Lab
----------------------------------------------------------------------------------------
*/
// We now support both latest and lower versions, due to Lifebit CloudOS is only support 20.04
// Note: NXF_VER=20.04.1 nextflow run main.nf -profile test,singularity
if( nextflow.version.matches(">= 20.07.1") ){
	nextflow.enable.dsl = 2
} else {
	// Support lower version of nextflow
	nextflow.preview.dsl = 2
}

include {helpMessage} from './modules/HELP'

// Show help message
if (params.help){
    helpMessage()
    exit 0
}

// Check mandatory params
if (! params.dsname)  exit 1, "Missing --dsname option for dataset name, check command help use --help"
if (! params.input)  exit 1, "Missing --input option for input data, check command help use --help"
//if ( !file(params.input.toString()).exists() )   exit 1, "input does not exist, check params: --input ${params.input}"

// Parse genome params
genome_map = params.genome_map

if (genome_map[params.genome]) { genome_path = genome_map[params.genome] }
else { 	genome_path = params.genome }

// infer dataType, chrSet based on reference genome name, hg - human, ecoli - ecoli, otherwise is other reference genome
humanChrSet = 'chr1,chr2,chr3,chr4,chr5,chr6,chr7,chr8,chr9,chr10,chr11,chr12,chr13,chr14,chr15,chr16,chr17,chr18,chr19,chr20,chr21,chr22,chrX,chrY'
if (params.genome.contains('hg') || (params.dataType && params.dataType == 'human')) {
	dataType = "human"
	if (!params.chrSet) {
		// default for human, if false or 'false' (string), using '  '
		chrSet = humanChrSet
	} else {
		chrSet = params.chrSet
	}
} else if (params.dataType && params.dataType == 'mouse') {
	dataType = "mouse"
	if (!params.chrSet) {
		// default for human, if false or 'false' (string), using '  '
		chrSet = humanChrSet
	} else {
		chrSet = params.chrSet
	}
} else if (params.genome.contains('ecoli') || (params.dataType && params.dataType == 'ecoli')) {
	dataType = "ecoli"
	if (!params.chrSet) {
		// default for ecoli
		chrSet = 'NC_000913.3'
	} else {
		chrSet = params.chrSet
	}
} else {
	// default will not found name, use other
	if (!params.dataType) { dataType = 'other' } else { dataType = params.dataType }
	if (!params.chrSet) {
		// No default value for other reference genome
		exit 1, "Missing --chrSet option for other reference genome, please specify chromosomes used in reference genome [${params.genome}]"
	}
	chrSet = params.chrSet
}

// chrSet1 and dataType1 is the infered params, defined from chrSet and dataType (not in scope of params)
params.chrSet1 = chrSet
params.dataType1 = dataType

// Get src and utils dir
projectDir = workflow.projectDir
ch_utils = Channel.fromPath("${projectDir}/utils",  type: 'dir', followLinks: false)
ch_src   = Channel.fromPath("${projectDir}/src",  type: 'dir', followLinks: false)

// Reference genome, chom size file
params.referenceGenome = "${params.GENOME_DIR}/${params.GENOME_FN}"
params.chromSizesFile = "${params.GENOME_DIR}/${params.CHROM_SIZE_FN}"

if (dataType == 'human') { isDeepModCluster = params.useDeepModCluster }
else { isDeepModCluster = false }
params.isDeepModCluster = isDeepModCluster


// Collect all folders of fast5 files, and send into Channels for pipelines
if (params.input.endsWith(".filelist.txt")) {
	// list of files in filelist.txt
	Channel.fromPath( params.input, checkIfExists: true )
		.splitCsv(header: false)
		.map {
			if (!file(it[0]).exists())  {
				log.warn "File not exists: ${it[0]}, check file list: ${params.input}"
			} else {
				return file(it[0])
			}
		}
		.set{ inputCh }
} else if (params.input.contains('*') || params.input.contains('?')) {
	// match all files in the folder, note: input must use quote string '', prevent expand in advance
	// such as --input '/fastscratch/liuya/nanome/NA12878/NA12878_CHR22/input_chr22/*'
	Channel.fromPath(params.input, type: 'any', checkIfExists: true)
		.set{ inputCh }
} else {
	// For single file/wildcard matched files
	Channel.fromPath( params.input, checkIfExists: true ).set{ inputCh }
}

// Header log info
def summary = [:]
summary['dsname'] 			= params.dsname
summary['input'] 			= params.input

if (genome_map[params.genome] != null) { summary['genome'] = "${params.genome} - [${genome_path}]" }
else { summary['genome'] = params.genome }

summary['\nRunning settings']         = "--------"
summary['processors'] 		= params.processors
summary['chrSet'] 			= chrSet   // .split(' ').join(',')
summary['dataType'] 		= dataType

if (params.runBasecall) summary['runBasecall'] = 'Yes'
if (params.skipBasecall) summary['skipBasecall'] = 'Yes'
if (params.runResquiggle) summary['runResquiggle'] = 'Yes'

if (params.runMethcall) {
	if (params.runNanopolish) summary['runNanopolish'] = 'Yes'
	if (params.runMegalodon) summary['runMegalodon'] = 'Yes'
	if (params.runDeepSignal) summary['runDeepSignal'] = 'Yes'
	if (params.runGuppy) summary['runGuppy'] = 'Yes'
	if (params.runTombo) summary['runTombo'] = 'Yes'
	if (params.runMETEORE) summary['runMETEORE'] = 'Yes'
	if (params.runDeepMod) summary['runDeepMod'] = 'Yes'

	if (params.runDeepMod) {
		summary['runDeepMod'] = 'Yes'
		if (params.moveOption)  summary['runDeepMod'] = summary['runDeepMod'] + ' + (move table)'
		if (isDeepModCluster)  {
			summary['runDeepMod'] = summary['runDeepMod'] + ' + (cluster model)'
		}
	}

	if (params.runNANOME) summary['runNANOME'] = 'Yes'

	if (params.runNewTool && params.newModuleConfigs)
		summary['runNewTool'] = params.newModuleConfigs.collect{it.name}.join(',')
}

if (params.cleanAnalyses) summary['cleanAnalyses'] = 'Yes'
if (params.deepsignalDir) { summary['deepsignalDir'] = params.deepsignalDir }
if (params.rerioDir) {
	summary['rerioDir'] = params.rerioDir
	summary['MEGALODON_MODEL'] = params.MEGALODON_MODEL
}
if (params.METEOREDir) { summary['METEOREDir'] = params.METEOREDir }
if (params.guppyDir) { summary['guppyDir'] 	= params.guppyDir }
if (params.tomboResquiggleOptions) { summary['tomboResquiggleOptions'] 	= params.tomboResquiggleOptions }

if (params.outputBam) { summary['outputBam'] 	= params.outputBam }
if (params.outputONTCoverage) { summary['outputONTCoverage'] 	= params.outputONTCoverage }
if (params.outputIntermediate) { summary['outputIntermediate'] 	= params.outputIntermediate }
if (params.outputRaw) { summary['outputRaw'] 	= params.outputRaw }
if (params.outputGenomeBrowser) { summary['outputGenomeBrowser'] 	= params.outputGenomeBrowser }
if (params.deduplicate) { summary['deduplicate'] 	= params.deduplicate }
if (params.sort) { summary['sort'] 	= params.sort }
if (params.multi_to_single_fast5) { summary['multi_to_single_fast5'] 	= params.multi_to_single_fast5 }
if (params.phasing) { summary['phasing'] 	= params.phasing }
if (params.hmc) { summary['hmc'] 	= params.hmc }
if (params.ctg_name) { summary['ctg_name'] 	= params.ctg_name }


summary['\nModel summary']         = "--------"
if (params.runBasecall && !params.skipBasecall) summary['GUPPY_BASECALL_MODEL'] 	= params.GUPPY_BASECALL_MODEL
if (params.runMethcall && params.runMegalodon)
	summary['MEGALODON_MODEL'] 	= params.rerio? 'Rerio:' + params.MEGALODON_MODEL : 'Remora:' + params.remoraModel
if (params.runMethcall && params.runDeepSignal) summary['DEEPSIGNAL_MODEL_DIR/DEEPSIGNAL_MODEL'] =\
 	params.DEEPSIGNAL_MODEL_DIR + "/" + params.DEEPSIGNAL_MODEL
if (params.runMethcall && params.runGuppy) summary['GUPPY_METHCALL_MODEL'] 	= params.GUPPY_METHCALL_MODEL
if (params.runMethcall && params.runDeepMod) {
	if (isDeepModCluster) {
		summary['DEEPMOD_RNN_MODEL;DEEPMOD_CLUSTER_MODEL'] = \
			"${params.DEEPMOD_RNN_MODEL};${params.DEEPMOD_CLUSTER_MODEL}"
		summary['DEEPMOD_CFILE'] = params.DEEPMOD_CFILE
	} else {
		summary['DEEPMOD_RNN_MODEL'] = "${params.DEEPMOD_RNN_MODEL}"
	}
}
if (params.runNANOME) {
	summary['NANOME_MODEL'] = "${params.NANOME_MODEL}"
	summary['CS_MODEL_FILE'] = "${params.CS_MODEL_FILE}"
	summary['CS_MODEL_SPEC'] = "${params.CS_MODEL_SPEC}"
}

summary['\nPipeline settings']         = "--------"
summary['Working dir'] 		= workflow.workDir
summary['Output dir']       = params.outdir
summary['Launch dir']       = workflow.launchDir
summary['Working dir']      = workflow.workDir
summary['Script dir']       = workflow.projectDir
summary['User']             = workflow.userName
summary['Profile']          = workflow.profile
summary['Config files'] 	= workflow.configFiles.join(',')
if (workflow.revision) summary['Pipeline Release'] = workflow.revision
if (workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['errorStrategy']    = params.errorStrategy
summary['maxRetries']       = params.maxRetries
if (params.echo)  		summary['echo'] = params.echo
if (params.cleanup)   	summary['cleanup'] = params.cleanup

if (workflow.profile.contains('hpc') || workflow.profile.contains('winter') ||\
 	workflow.profile.contains('sumner') ) {
	summary['\nHPC settings']         = "--------"
    summary['queue']        = params.queue
    summary['qos']          = params.qos
    summary['memory']       = params.memory
    summary['time']         = params.time
    summary['queueSize']    = params.queueSize
    if (params.gresOptions) {summary['gresOptions'] = params.gresOptions }
}
if (workflow.profile.contains('google') || (params.config && params.config.contains('lifebit'))) {
	summary['\nGCP settings']         = "--------"
	if (params.projectCloud) {
		summary['projectCloud']    = params.projectCloud
	}
	if (params.config) { // lifebit specific settings
		summary['config']       		= params.config
	}
	summary['networkCloud']       = params.networkCloud
	summary['subnetworkCloud']	= params.subnetworkCloud

    summary['locationCloud']          = params.locationCloud
    summary['regionCloud']            = params.regionCloud
    summary['zoneCloud']       		= params.zoneCloud

    summary['bootDiskSizeCloud']       = params.bootDiskSizeCloud

	if (params.machineType)   	summary['machineType'] = params.machineType
	else {
		summary['machineType:cpus']         	= params.processors
		summary['machineType:memory']         	= params.memory
	}
	summary['gpuType']         	= params.gpuType
	summary['gpuNumber']        = params.gpuNumber

	// summary['lowDiskSize']      = params.lowDiskSize
	summary['midDiskSize']      = params.midDiskSize
	summary['highDiskSize']     = params.highDiskSize
}

log.info """\
NANOME - NF PIPELINE (v$workflow.manifest.version)
by Li Lab at The Jackson Laboratory
https://github.com/LabShengLi/nanome
================================="""
.stripIndent()

log.info summary.collect { k,v -> "${k.padRight(20)}: $v" }.join("\n")
log.info "================================="


include { ENVCHECK } from './modules/ENVCHECK'  // addParams(chrSet1: "${chrSet}", dataType1:"${dataType}")

include { UNTAR } from './modules/UNTAR'

include { BASECALL } from './modules/BASECALL'

include { ALIGNMENT } from './modules/ALIGNMENT'

include { QCEXPORT } from './modules/QCEXPORT'

include { RESQUIGGLE } from './modules/RESQUIGGLE'

include { NANOPOLISH; NPLSHCOMB } from './modules/NANOPOLISH'

include { MEGALODON; MGLDNCOMB } from './modules/MEGALODON'

include { DEEPSIGNAL; DPSIGCOMB } from './modules/DEEPSIGNAL'

include { DEEPSIGNAL2; DEEPSIGNAL2COMB } from './modules/DEEPSIGNAL2'

include { REPORT } from './modules/REPORT'

include { Guppy; GuppyComb; Tombo; TomboComb; DeepMod; DpmodComb; METEORE } from './modules/OLDTOOLS'

include { NewTool; NewToolComb } from './modules/NEWTOOLS'

include { CLAIR3; PHASING } from './modules/PHASING'


workflow {
	if ( !file(genome_path.toString()).exists() )
		exit 1, "genome reference path does not exist, check params: --genome ${params.genome}"

	genome_ch = Channel.fromPath(genome_path, type: 'any', checkIfExists: true)

	if (!params.rerioDir) { // default if null, will online downloading
		// This is only a place holder for input
		rerioDir = Channel.fromPath("${projectDir}/utils/null1", type: 'any', checkIfExists: false)
	} else {
		// User provide the dir
		if ( !file(params.rerioDir.toString()).exists() )
			exit 1, "rerioDir does not exist, check params: --rerioDir ${params.rerioDir}"
		rerioDir = Channel.fromPath(params.rerioDir, type: 'any', checkIfExists: true)
	}

	if (! params.runDeepSignal) {
		// use null placeholder
		deepsignalDir = Channel.fromPath("${projectDir}/utils/null2", type: 'any', checkIfExists: true)
	} else if (!params.deepsignalDir) {
		// default if null, will online staging
		deepsignalDir = Channel.fromPath(params.DEEPSIGNAL_MODEL_ONLINE, type: 'any', checkIfExists: true)
	} else {
		// User provide the dir
		if ( !file(params.deepsignalDir.toString()).exists() )
			exit 1, "deepsignalDir does not exist, check params: --deepsignalDir ${params.deepsignalDir}"
		deepsignalDir = Channel.fromPath(params.deepsignalDir, type: 'any', checkIfExists: true)
	}

	ENVCHECK(genome_ch, ch_utils, rerioDir, deepsignalDir)
	UNTAR(inputCh)

	if (params.runBasecall) {
		BASECALL(UNTAR.out.untar)
		ALIGNMENT(BASECALL.out.basecall, ENVCHECK.out.reference_genome)
		QCEXPORT(BASECALL.out.basecall.collect(),
					ALIGNMENT.out.alignment.collect(),
					ENVCHECK.out.reference_genome)
	}

	// Resquiggle running if use Tombo or DeepSignal
	if (((params.runDeepSignal || params.runTombo || params.runDeepSignal2) && params.runMethcall) || params.runResquiggle) {
		// BASECALL.out.basecall.subscribe({ println("BASECALL.out.basecall: $it") })
		resquiggle = RESQUIGGLE(BASECALL.out.basecall, ENVCHECK.out.reference_genome)
		if (params.feature_extract)
			f1 = resquiggle.feature_extract
		else
			f1 = Channel.empty()
	} else {
		f1 = Channel.empty()
	}

	if (params.runNanopolish && params.runMethcall) {
		NANOPOLISH(BASECALL.out.basecall_tuple.join(ALIGNMENT.out.alignment_tuple), ENVCHECK.out.reference_genome)
		comb_nanopolish = NPLSHCOMB(NANOPOLISH.out.nanopolish_tsv.collect(), ch_src, ch_utils)
		s1 = comb_nanopolish.site_unify
		r1 = comb_nanopolish.read_unify
	} else {
		s1 = Channel.empty()
		r1 = Channel.empty()
	}

	if (params.runMegalodon && params.runMethcall) {
		MEGALODON(UNTAR.out.untar, ENVCHECK.out.reference_genome, ENVCHECK.out.rerio)
		comb_megalodon = MGLDNCOMB(MEGALODON.out.megalodon_tsv.collect(),
							MEGALODON.out.megalodon_mod_mappings.collect(),
							ch_src, ch_utils)
		s2 = comb_megalodon.site_unify
		r2 = comb_megalodon.read_unify
	} else {
		s2 = Channel.empty()
		r2 = Channel.empty()
	}

	if (params.runDeepSignal && params.runMethcall) {
		DEEPSIGNAL(RESQUIGGLE.out.resquiggle, ENVCHECK.out.reference_genome,
					ENVCHECK.out.deepsignal_model)
		comb_deepsignal = DPSIGCOMB(DEEPSIGNAL.out.deepsignal_tsv.collect(), ch_src, ch_utils)
		s3 = comb_deepsignal.site_unify
		r3 = comb_deepsignal.read_unify
	} else {
		s3 = Channel.empty()
		r3 = Channel.empty()
	}

	if (params.runDeepSignal2 && params.runMethcall) {
		deepsignal2 = DEEPSIGNAL2(RESQUIGGLE.out.resquiggle.collect(),
					ENVCHECK.out.reference_genome,
					ch_src, ch_utils)
		DEEPSIGNAL2COMB(DEEPSIGNAL2.out.deepsignal2_combine_out,
						ch_src, ch_utils
						)
		f2 = deepsignal2.deepsignal2_feature_out
	} else {
		f2 = Channel.empty()
	}

	if (params.runGuppy && params.runMethcall) {
		Guppy(UNTAR.out.untar, ENVCHECK.out.reference_genome, ch_utils)

		gcf52ref_ch = Channel.fromPath("${projectDir}/utils/null1").concat(Guppy.out.guppy_gcf52ref_tsv.collect())

		comb_guppy = GuppyComb(Guppy.out.guppy_fast5mod_bam.collect(),
								gcf52ref_ch,
								ENVCHECK.out.reference_genome,
								ch_src, ch_utils)
		s4 = comb_guppy.site_unify
		r4 = comb_guppy.read_unify
	} else {
		s4 = Channel.empty()
		r4 = Channel.empty()
	}

	if (params.runTombo && params.runMethcall) {
		Tombo(RESQUIGGLE.out.resquiggle, ENVCHECK.out.reference_genome)
		comb_tombo = TomboComb(Tombo.out.tombo_tsv.collect(), ch_src, ch_utils)
		s5 = comb_tombo.site_unify
		r5 = comb_tombo.read_unify
	} else {
		s5 = Channel.empty()
		r5 = Channel.empty()
	}

	if (params.runDeepMod && params.runMethcall) {
		if (!isDeepModCluster) {
			// not use cluster model, only a place holder here
			ch_ctar = Channel.fromPath("${projectDir}/utils/null1", type:'any', checkIfExists: false)
		} else {
			if ( !file(params.DEEPMOD_CFILE.toString()).exists() )
				exit 1, "DEEPMOD_CFILE does not exist, check params: --DEEPMOD_CFILE ${params.DEEPMOD_CFILE}"
			ch_ctar = Channel.fromPath(params.DEEPMOD_CFILE, type:'any', checkIfExists: true)
		}
		DeepMod(BASECALL.out.basecall, ENVCHECK.out.reference_genome)
		comb_deepmod = DpmodComb(DeepMod.out.deepmod_out.collect(), ch_ctar, ch_src, ch_utils)
		s6 = comb_deepmod.site_unify
	} else {
		s6 = Channel.empty()
	}

	if (params.runMETEORE && params.runMethcall) {
		// Read level combine a list for top3 used by METEORE
		if (!params.METEOREDir) {
			METEOREDir_ch = Channel.fromPath(params.METEORE_GITHUB_ONLINE, type: 'any', checkIfExists: true)
		} else {
			if ( !file(params.METEOREDir.toString()).exists() )
				exit 1, "METEOREDir does not exist, check params: --METEOREDir ${params.METEOREDir}"
			METEOREDir_ch = Channel.fromPath(params.METEOREDir, type: 'any', checkIfExists: true)
		}
		METEORE(r1, r2, r3, ch_src, ch_utils, METEOREDir_ch)
		s7 = METEORE.out.site_unify
		r7 = METEORE.out.read_unify
	} else {
		s7 = Channel.empty()
		r7 = Channel.empty()
	}

	if (params.runNewTool && params.newModuleConfigs) {
		newModuleCh = Channel.of( params.newModuleConfigs ).flatten()
		// ref: https://www.nextflow.io/docs/latest/operator.html#combine
		NewTool(newModuleCh.combine(BASECALL.out.basecall), ENVCHECK.out.reference_genome, params.referenceGenome)
		NewToolComb(NewTool.out.batch_out.collect(), newModuleCh, ch_src)

		s_new = NewToolComb.out.site_unify
		r_new = NewToolComb.out.read_unify
	} else {
		s_new = Channel.empty()
		r_new = Channel.empty()
	}

	// Site level combine a list
	Channel.fromPath("${projectDir}/utils/null1").concat(
		s1, s2, s3, s4, s5, s6, s7, s_new
		).toList().set { tools_site_unify }

	Channel.fromPath("${projectDir}/utils/null2").concat(
		r1, r2, r3, f1, f2
		).toList().set { tools_read_unify }

	REPORT(tools_site_unify, tools_read_unify,
			ENVCHECK.out.tools_version_tsv, QCEXPORT.out.qc_report,
			ENVCHECK.out.reference_genome, ch_src, ch_utils)

	if (params.phasing) {
		CLAIR3(QCEXPORT.out.bam_data, ENVCHECK.out.reference_genome)
		Channel.fromPath("${projectDir}/utils/null1").concat(
			MGLDNCOMB.out.megalodon_combine, REPORT.out.nanome_combine_out
			).toList().set { mega_and_nanome_ch }
		PHASING(mega_and_nanome_ch, CLAIR3.out.clair3_out_ch,
				ch_src, QCEXPORT.out.bam_data, ENVCHECK.out.reference_genome)
	}
}
