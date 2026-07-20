# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------

PROJECT          ?=
TOP_LEVEL        ?=
OUT_DIR          ?= no_name
NETLIST_DIR      ?= no_name
VCD_DIR          ?= no_name
CLK_PERIOD_NS    ?= 1
PARAMS           ?= none
KEEP_HIERARCHY   ?= 0
KEEP_MODULES     ?= none
BLACKBOX_MODULES ?= none
VCD              ?= 0

PROJ_DIR := $(REPO_HOME)/projects/$(PROJECT)

export SEL_PROJECT          := $(PROJECT)
export SEL_TOP_LEVEL        := $(TOP_LEVEL)
export SEL_OUT_DIR          := $(OUT_DIR)
export SEL_NETLIST_DIR      := $(NETLIST_DIR)
export SEL_VCD_DIR          := $(VCD_DIR)
export SEL_CLK_PERIOD_NS    := $(CLK_PERIOD_NS)
export SEL_PARAMS           := $(PARAMS)
export SEL_KEEP_HIERARCHY   := $(KEEP_HIERARCHY)
export SEL_KEEP_MODULES     := $(KEEP_MODULES)
export SEL_BLACKBOX_MODULES := $(BLACKBOX_MODULES)
export SEL_VCD              := $(VCD)

.PHONY: init sim syn post-syn-sta post-syn-sim post-syn-dpa clean-all clean-sim clean-imp

init:
	mkdir -p $(PROJ_DIR)/sim
	mkdir -p $(PROJ_DIR)/imp

sim: clean-sim
	cd $(REPO_HOME)/scripts/sim && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR)/build && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR)/output && \
	./run.sh && \
	if [ -f $(REPO_HOME)/scripts/sim/activity.vcd ]; then \
	mv $(REPO_HOME)/scripts/sim/activity.vcd $(PROJ_DIR)/sim/$(OUT_DIR)/output; \
	fi

syn: clean-imp
	cd $(REPO_HOME)/scripts/syn && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/output && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/report && \
	yosys -l $(PROJ_DIR)/imp/$(OUT_DIR)/output/yosys.log -c $(REPO_HOME)/scripts/syn/run.tcl

post-syn-sta: clean-imp
	cd $(REPO_HOME)/scripts/post-syn-sta && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/report && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/output && \
	sta -no_splash -exit $(REPO_HOME)/scripts/post-syn-sta/run.tcl | tee $(PROJ_DIR)/imp/$(OUT_DIR)/output/opensta.log

post-syn-sim: clean-sim
	cd $(REPO_HOME)/scripts/post-syn-sim && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR)/build && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR)/output && \
	./run.sh && \
	if [ -f $(REPO_HOME)/scripts/post-syn-sim/activity.vcd ]; then \
	mv $(REPO_HOME)/scripts/post-syn-sim/activity.vcd $(PROJ_DIR)/sim/$(OUT_DIR)/output; \
	fi

post-syn-dpa: clean-imp
	cd $(REPO_HOME)/scripts/post-syn-dpa && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/report && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/output && \
	sta -no_splash -exit $(REPO_HOME)/scripts/post-syn-dpa/run.tcl | tee $(PROJ_DIR)/imp/$(OUT_DIR)/output/opensta.log

clean-all:
	rm -rf $(PROJ_DIR)/sim
	rm -rf $(PROJ_DIR)/imp

clean-sim:
	rm -rf $(PROJ_DIR)/sim/$(OUT_DIR)

clean-imp:
	rm -rf $(PROJ_DIR)/imp/$(OUT_DIR)
