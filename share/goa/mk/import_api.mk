#!/usr/bin/make -f

ARCH    ?= x86_64
REP_DIR ?= $(firstword $(REPOSITORIES))

select_from_repositories = $(firstword $(foreach REP,$(REPOSITORIES),$(wildcard $(REP)/$(1))))
select_from_ports        = $(REP_DIR)

# set up SPECS
BASE_DIR := $(TOOL_DIR)
SPECS := $(ARCH)
include $(BASE_DIR)/mk/spec/$(ARCH).mk

include $(IMPORT_MK)

ALL_INC_DIR := $(INC_DIR)
ALL_INC_DIR += $(foreach DIR,$(REP_INC_DIR), $(foreach REP,$(REPOSITORIES),$(REP)/$(DIR)))
ALL_INC_DIR += $(foreach REP,$(REPOSITORIES),$(REP)/include)

include_dirs:
	@echo ${ALL_INC_DIR}
