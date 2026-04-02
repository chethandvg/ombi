# =============================================================================
# OMBI — Ordered Minimum via Bitmap Indexing
# =============================================================================
#
# Build all SSSP implementations for DIMACS benchmark comparison.
#
# Usage:
#   make              # build OMBI (timing + checksum)
#   make all          # build everything (OMBI + all baselines)
#   make baselines    # build all 8 baseline implementations
#   make smartq       # build Goldberg's Smart Queue
#   make clean        # remove all binaries
#
# Compiler flags match Goldberg's build exactly for fair comparison.
# =============================================================================

CXX       = g++
CXXFLAGS  = -std=c++17 -Wall -O3 -DNDEBUG
LDFLAGS   = -lm

# --- Source directories ---
OMBI_DIR  = src/ombi
BASE_DIR  = src/baselines
INFRA_DIR = src/infrastructure
SQ_DIR    = src/baselines/smartq
TOOLS_DIR = src/tools

# --- Shared infrastructure sources ---
INFRA_SRC = $(INFRA_DIR)/parser_gr.cc $(INFRA_DIR)/timer.cc $(INFRA_DIR)/parser_ss.cc

# --- Output directory for binaries ---
BIN_DIR   = bin

# =============================================================================
# Phony targets
# =============================================================================
.PHONY: all ombi baselines smartq tools clean help

help:
	@echo ""
	@echo "  OMBI — Build Targets"
	@echo "  ════════════════════════════════════════════"
	@echo ""
	@echo "  make              Build OMBI (timing + checksum)"
	@echo "  make all          Build everything"
	@echo "  make baselines    Build all 8 baseline Dijkstra variants"
	@echo "  make smartq       Build Goldberg's Smart Queue"
	@echo "  make tools        Build utility programs"
	@echo "  make clean        Remove all binaries"
	@echo ""
	@echo "  Individual baselines:"
	@echo "    make bin/dij_bh    Binary Heap"
	@echo "    make bin/dij_4h    4-ary Heap"
	@echo "    make bin/dij_fh    Fibonacci Heap"
	@echo "    make bin/dij_ph    Pairing Heap"
	@echo "    make bin/dij_dial  Dial's Algorithm"
	@echo "    make bin/dij_r1    1-Level Radix Heap"
	@echo "    make bin/dij_r2    2-Level Radix Heap"
	@echo "    make bin/dij_ch    Contraction Hierarchies"
	@echo ""

# =============================================================================
# Default: build OMBI
# =============================================================================
ombi: $(BIN_DIR)/ombi $(BIN_DIR)/ombiC

# =============================================================================
# All: OMBI + baselines + Smart Queue + tools
# =============================================================================
all: ombi baselines smartq tools

# =============================================================================
# OMBI — core algorithm
# =============================================================================
$(BIN_DIR):
	mkdir -p $(BIN_DIR)

# Standard OMBI (uses ombi.cc — simpler, slightly slower)
$(BIN_DIR)/ombi: $(OMBI_DIR)/main.cc $(OMBI_DIR)/ombi.cc $(OMBI_DIR)/ombi.h $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -I$(INFRA_DIR) -o $@ $(OMBI_DIR)/main.cc $(OMBI_DIR)/ombi.cc $(INFRA_SRC) $(LDFLAGS)

$(BIN_DIR)/ombiC: $(OMBI_DIR)/main.cc $(OMBI_DIR)/ombi.cc $(OMBI_DIR)/ombi.h $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DCHECKSUM -I$(INFRA_DIR) -o $@ $(OMBI_DIR)/main.cc $(OMBI_DIR)/ombi.cc $(INFRA_SRC) $(LDFLAGS)

# Optimized OMBI (uses ombi_opt.cc — packed state, force-inlined hot path)
$(BIN_DIR)/ombi_opt: $(OMBI_DIR)/main.cc $(OMBI_DIR)/ombi_opt.cc $(OMBI_DIR)/ombi_opt.h $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DOMBI_OPT -I$(INFRA_DIR) -o $@ $(OMBI_DIR)/main.cc $(OMBI_DIR)/ombi_opt.cc $(INFRA_SRC) $(LDFLAGS)

$(BIN_DIR)/ombi_optC: $(OMBI_DIR)/main.cc $(OMBI_DIR)/ombi_opt.cc $(OMBI_DIR)/ombi_opt.h $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DOMBI_OPT -DCHECKSUM -I$(INFRA_DIR) -o $@ $(OMBI_DIR)/main.cc $(OMBI_DIR)/ombi_opt.cc $(INFRA_SRC) $(LDFLAGS)

# OMBI v2 with Caliber/F-set (uses ombi_opt2.cc)
$(BIN_DIR)/ombi_v2: $(OMBI_DIR)/main.cc $(OMBI_DIR)/ombi_opt2.cc $(OMBI_DIR)/ombi_opt2.h $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DOMBI_V2 -I$(INFRA_DIR) -o $@ $(OMBI_DIR)/main.cc $(OMBI_DIR)/ombi_opt2.cc $(INFRA_SRC) $(LDFLAGS)

$(BIN_DIR)/ombi_v2C: $(OMBI_DIR)/main.cc $(OMBI_DIR)/ombi_opt2.cc $(OMBI_DIR)/ombi_opt2.h $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DOMBI_V2 -DCHECKSUM -I$(INFRA_DIR) -o $@ $(OMBI_DIR)/main.cc $(OMBI_DIR)/ombi_opt2.cc $(INFRA_SRC) $(LDFLAGS)

# =============================================================================
# Baselines — 8 Dijkstra variants
# =============================================================================
baselines: $(BIN_DIR)/dij_bh $(BIN_DIR)/dij_bhC \
           $(BIN_DIR)/dij_4h $(BIN_DIR)/dij_4hC \
           $(BIN_DIR)/dij_fh $(BIN_DIR)/dij_fhC \
           $(BIN_DIR)/dij_ph $(BIN_DIR)/dij_phC \
           $(BIN_DIR)/dij_dial $(BIN_DIR)/dij_dialC \
           $(BIN_DIR)/dij_r1 $(BIN_DIR)/dij_r1C \
           $(BIN_DIR)/dij_r2 $(BIN_DIR)/dij_r2C \
           $(BIN_DIR)/dij_ch $(BIN_DIR)/dij_chC

# Binary Heap
$(BIN_DIR)/dij_bh: $(BASE_DIR)/dijkstra_bh.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_bh.cc $(INFRA_SRC) $(LDFLAGS)
$(BIN_DIR)/dij_bhC: $(BASE_DIR)/dijkstra_bh.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DCHECKSUM -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_bh.cc $(INFRA_SRC) $(LDFLAGS)

# 4-ary Heap
$(BIN_DIR)/dij_4h: $(BASE_DIR)/dijkstra_4h.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_4h.cc $(INFRA_SRC) $(LDFLAGS)
$(BIN_DIR)/dij_4hC: $(BASE_DIR)/dijkstra_4h.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DCHECKSUM -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_4h.cc $(INFRA_SRC) $(LDFLAGS)

# Fibonacci Heap
$(BIN_DIR)/dij_fh: $(BASE_DIR)/dijkstra_fh.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_fh.cc $(INFRA_SRC) $(LDFLAGS)
$(BIN_DIR)/dij_fhC: $(BASE_DIR)/dijkstra_fh.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DCHECKSUM -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_fh.cc $(INFRA_SRC) $(LDFLAGS)

# Pairing Heap
$(BIN_DIR)/dij_ph: $(BASE_DIR)/dijkstra_ph.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_ph.cc $(INFRA_SRC) $(LDFLAGS)
$(BIN_DIR)/dij_phC: $(BASE_DIR)/dijkstra_ph.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DCHECKSUM -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_ph.cc $(INFRA_SRC) $(LDFLAGS)

# Dial's Algorithm
$(BIN_DIR)/dij_dial: $(BASE_DIR)/dijkstra_dial.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_dial.cc $(INFRA_SRC) $(LDFLAGS)
$(BIN_DIR)/dij_dialC: $(BASE_DIR)/dijkstra_dial.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DCHECKSUM -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_dial.cc $(INFRA_SRC) $(LDFLAGS)

# 1-Level Radix Heap
$(BIN_DIR)/dij_r1: $(BASE_DIR)/dijkstra_radix1.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_radix1.cc $(INFRA_SRC) $(LDFLAGS)
$(BIN_DIR)/dij_r1C: $(BASE_DIR)/dijkstra_radix1.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DCHECKSUM -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_radix1.cc $(INFRA_SRC) $(LDFLAGS)

# 2-Level Radix Heap
$(BIN_DIR)/dij_r2: $(BASE_DIR)/dijkstra_radix2.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_radix2.cc $(INFRA_SRC) $(LDFLAGS)
$(BIN_DIR)/dij_r2C: $(BASE_DIR)/dijkstra_radix2.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DCHECKSUM -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_radix2.cc $(INFRA_SRC) $(LDFLAGS)

# Contraction Hierarchies
$(BIN_DIR)/dij_ch: $(BASE_DIR)/dijkstra_ch.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_ch.cc $(INFRA_SRC) $(LDFLAGS)
$(BIN_DIR)/dij_chC: $(BASE_DIR)/dijkstra_ch.cc $(INFRA_DIR)/nodearc.h $(INFRA_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DCHECKSUM -I$(INFRA_DIR) -o $@ $(BASE_DIR)/dijkstra_ch.cc $(INFRA_SRC) $(LDFLAGS)

# =============================================================================
# Goldberg's Smart Queue (separate build — uses its own infrastructure)
# =============================================================================
smartq: $(BIN_DIR)/sq $(BIN_DIR)/sqC

$(BIN_DIR)/sq: $(SQ_DIR)/main.cc $(SQ_DIR)/smartq.cc $(SQ_DIR)/sp.cc $(SQ_DIR)/parser_gr.cc $(SQ_DIR)/timer.cc $(SQ_DIR)/parser_ss.cc | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -I$(SQ_DIR) -o $@ $(SQ_DIR)/main.cc $(SQ_DIR)/smartq.cc $(SQ_DIR)/sp.cc \
		$(SQ_DIR)/parser_gr.cc $(SQ_DIR)/timer.cc $(SQ_DIR)/parser_ss.cc $(LDFLAGS)

$(BIN_DIR)/sqC: $(SQ_DIR)/main.cc $(SQ_DIR)/smartq.cc $(SQ_DIR)/sp.cc $(SQ_DIR)/parser_gr.cc $(SQ_DIR)/timer.cc $(SQ_DIR)/parser_ss.cc | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -DCHECKSUM -I$(SQ_DIR) -o $@ $(SQ_DIR)/main.cc $(SQ_DIR)/smartq.cc $(SQ_DIR)/sp.cc \
		$(SQ_DIR)/parser_gr.cc $(SQ_DIR)/timer.cc $(SQ_DIR)/parser_ss.cc $(LDFLAGS)

# =============================================================================
# Tools
# =============================================================================
tools: $(BIN_DIR)/gen_grid

$(BIN_DIR)/gen_grid: $(TOOLS_DIR)/gen_grid.cc | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $(TOOLS_DIR)/gen_grid.cc $(LDFLAGS)

# =============================================================================
# Clean
# =============================================================================
clean:
	rm -rf $(BIN_DIR)
