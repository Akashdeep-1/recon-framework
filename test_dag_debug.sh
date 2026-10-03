#!/usr/bin/env bash

source /d/recon-framework-main/lib/dag.sh
dag_load_canonical
echo "DAG_STAGE_ID: ${DAG_STAGE_ID[*]}"
echo "DAG_STAGE_DEPS: ${DAG_STAGE_DEPS[*]}"
echo "DAG_STAGE_DEPS[0]: ${DAG_STAGE_DEPS[0]}"
echo "DAG_STAGE_DEPS[1]: ${DAG_STAGE_DEPS[1]}"
echo "DAG_STAGE_DEPS[2]: ${DAG_STAGE_DEPS[2]}"
echo "DAG_STAGE_DEPS[3]: ${DAG_STAGE_DEPS[3]}"
echo "DAG_STAGE_DEPS[4]: ${DAG_STAGE_DEPS[4]}"
echo "DAG_STAGE_DEPS[5]: ${DAG_STAGE_DEPS[5]}"
echo "DAG_STAGE_DEPS[6]: ${DAG_STAGE_DEPS[6]}"
dag_detect_cycles >/dev/null
echo "Result: $?"
echo "Topo: ${DAG_TOPO_ORDER[*]}"