#!/bin/bash
#SBATCH --job-name=nanome.ecoli.hpc
#SBATCH -p gpu
#SBATCH --gres=gpu:v100:1
#SBATCH -q inference
#SBATCH -N 1 # number of nodes
#SBATCH -n 1 # number of cores
#SBATCH --mem=20G # memory pool for all cores
#SBATCH --time=02:00:00 # time
#SBATCH --output=log/%x.%j.log # STDOUT & STDERR

date; hostname; pwd

# Base directory of running and output for nanome
baseDir=${1:-/fastscratch/li-lab/nanome}

workDir=${baseDir}/work-ecoli
outputsDir=${baseDir}/outputs-ecoli

########################################
########################################
# Clean old results
rm -rf ${workDir} ${outputsDir}

########################################
########################################
# Running pipeline for E. coli data
module load singularity
set -x
nextflow run main.nf\
    -profile singularity,hpc\
    -work-dir ${workDir}\
    --outputDir ${outputsDir}\
    -config conf/jax_hpc.config,conf/ecoli_demo.config\
    --cleanCache false

# Report
tree ${workDir} > ${baseDir}/work_ecoli_filetree.txt
tree ${outputsDir} > ${baseDir}/outputs_ecoli_filetree.txt

echo "### nanome pipeline for ecoli data on HPC DONE"
