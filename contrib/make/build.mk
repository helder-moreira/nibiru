
###############################################################################
###                               Build Flags                               ###
###############################################################################

# BRANCH: Current git branch
# COMMIT: Current commit hash
BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
COMMIT := $(shell git log -1 --format='%H')

VERSION ?= $(shell git describe --tags --abbrev=0)
ifeq ($(strip $(VERSION)),)
  VERSION := $(BRANCH)-$(COMMIT)
endif

OS_NAME := $(shell uname -s | tr A-Z a-z)
ifeq ($(OS_NAME),darwin)
	ARCH_NAME := all
else ifeq ($(shell uname -m),x86_64)
	ARCH_NAME := amd64
else
	ARCH_NAME := arm64
endif
SUDO := $(shell if [ "$(shell id -u)" != "0" ]; then echo "sudo"; fi)

CMT_VERSION := $(shell go list -m github.com/cometbft/cometbft | sed 's:.* ::')
ROCKSDB_VERSION := 8.9.1
WASMVM_VERSION := $(shell go list -m github.com/CosmWasm/wasmvm | awk '{sub(/^v/, "", $$2); print $$2}')
BUILDDIR ?= $(CURDIR)/build
TEMPDIR ?= $(CURDIR)/temp

export GO111MODULE = on

# process build tags
build_tags = netgo osusergo ledger static rocksdb pebbledb
ifeq ($(OS_NAME),darwin)
	build_tags += static_wasm grocksdb_no_link
else
	build_tags += muslc
endif
build_tags := $(strip $(build_tags))

whitespace :=
whitespace += $(whitespace)
comma := ,
build_tags_comma_sep := $(subst $(whitespace),$(comma),$(build_tags))

# process linker flags
ldflags = -X github.com/cosmos/cosmos-sdk/version.Name=nibiru \
		  -X github.com/cosmos/cosmos-sdk/version.AppName=nibid \
		  -X github.com/cosmos/cosmos-sdk/version.Version=$(VERSION) \
		  -X github.com/cosmos/cosmos-sdk/version.Commit=$(COMMIT) \
		  -X "github.com/cosmos/cosmos-sdk/version.BuildTags=$(build_tags_comma_sep)" \
		  -X github.com/cometbft/cometbft/version.CMTSemVer=$(CMT_VERSION) \
		  -X github.com/cosmos/cosmos-sdk/types.DBBackend=pebbledb \
		  -linkmode=external \
		  -w -s

ldflags := $(strip $(ldflags))

BUILD_FLAGS := -tags "$(build_tags)" -ldflags '$(ldflags)'
CGO_CFLAGS  := -I$(TEMPDIR)/rocksdb/$(ROCKSDB_VERSION)/include
CGO_LDFLAGS := -L$(TEMPDIR)/rocksdb/$(ROCKSDB_VERSION)/lib/$(OS_NAME)_$(ARCH_NAME)/ -L$(TEMPDIR)/wasmvm/$(WASMVM_VERSION)/lib/$(OS_NAME)_$(ARCH_NAME)/
ifeq ($(OS_NAME),darwin)
	CGO_LDFLAGS += -lrocksdb -lstdc++ -lz -lbz2
else
	CGO_LDFLAGS += -static -lm -lbz2
endif

###############################################################################
###                                  Build                                  ###
###############################################################################

$(TEMPDIR)/:
	mkdir -p $(TEMPDIR)/

# download required libs
rocksdblib: $(TEMPDIR)/
	@mkdir -p $(TEMPDIR)/rocksdb/$(ROCKSDB_VERSION)/include
	@mkdir -p $(TEMPDIR)/rocksdb/$(ROCKSDB_VERSION)/lib/$(OS_NAME)_$(ARCH_NAME)/
	@if [ ! -d $(TEMPDIR)/rocksdb/$(ROCKSDB_VERSION)/include/rocksdb ] ; \
	then \
	  wget https://github.com/NibiruChain/gorocksdb/releases/download/v$(ROCKSDB_VERSION)/include.$(ROCKSDB_VERSION).tar.gz -O - | tar -xz -C $(TEMPDIR)/rocksdb/$(ROCKSDB_VERSION)/include/; \
	fi
	@if [ ! -f $(TEMPDIR)/rocksdb/$(ROCKSDB_VERSION)/lib/$(OS_NAME)_$(ARCH_NAME)/librocksdb.a ] ; \
	then \
	  wget https://github.com/NibiruChain/gorocksdb/releases/download/v$(ROCKSDB_VERSION)/librocksdb_$(ROCKSDB_VERSION)_$(OS_NAME)_$(ARCH_NAME).tar.gz -O - | tar -xz -C $(TEMPDIR)/rocksdb/$(ROCKSDB_VERSION)/lib/$(OS_NAME)_$(ARCH_NAME)/; \
	fi

wasmvmlib: $(TEMPDIR)/
	@mkdir -p $(TEMPDIR)/wasmvm/$(WASMVM_VERSION)/lib/$(OS_NAME)_$(ARCH_NAME)/
	@if [ ! -f $(TEMPDIR)/wasmvm/$(WASMVM_VERSION)/lib/$(OS_NAME)_$(ARCH_NAME)/libwasmvm*.a ] ; \
	then \
	  if [ "$(OS_NAME)" = "darwin" ] ; \
	  then \
	    wget https://github.com/CosmWasm/wasmvm/releases/download/v$(WASMVM_VERSION)/libwasmvmstatic_darwin.a -O $(TEMPDIR)/wasmvm/$(WASMVM_VERSION)/lib/$(OS_NAME)_$(ARCH_NAME)/libwasmvmstatic_darwin.a; \
	  else \
		if [ "$(ARCH_NAME)" = "amd64" ] ; \
		then \
		  wget https://github.com/CosmWasm/wasmvm/releases/download/v$(WASMVM_VERSION)/libwasmvm_muslc.x86_64.a -O $(TEMPDIR)/wasmvm/$(WASMVM_VERSION)/lib/$(OS_NAME)_$(ARCH_NAME)/libwasmvm_muslc.a; \
		else \
		  wget https://github.com/CosmWasm/wasmvm/releases/download/v$(WASMVM_VERSION)/libwasmvm_muslc.aarch64.a -O $(TEMPDIR)/wasmvm/$(WASMVM_VERSION)/lib/$(OS_NAME)_$(ARCH_NAME)/libwasmvm_muslc.a; \
		fi; \
	  fi; \
	fi

packages:
	@if [ "$(OS_NAME)" = "linux" ] ; \
	then \
	  if [ -f /etc/debian_version ] ; \
      then \
        $(SUDO) apt-get update; \
        dpkg -s liblz4-dev > /dev/null 2>&1 || $(SUDO) apt-get install --no-install-recommends -y liblz4-dev; \
        dpkg -s libsnappy-dev > /dev/null 2>&1 || $(SUDO) apt-get install --no-install-recommends -y libsnappy-dev; \
        dpkg -s zlib1g-dev > /dev/null 2>&1 || $(SUDO) apt-get install --no-install-recommends -y zlib1g-dev; \
        dpkg -s libbz2-dev > /dev/null 2>&1 || $(SUDO) apt-get install --no-install-recommends -y libbz2-dev; \
        dpkg -s libzstd-dev > /dev/null 2>&1 || $(SUDO) apt-get install --no-install-recommends -y libzstd-dev; \
      else \
	    echo "Please make sure you have installed the following libraries: lz4, snappy, z, bz2, zstd"; \
      fi; \
    fi

# command for make build and make install
build: BUILDARGS=-o $(BUILDDIR)/
build install: go.sum $(BUILDDIR)/ rocksdblib wasmvmlib packages
	CGO_ENABLED=1 CGO_CFLAGS="$(CGO_CFLAGS)" CGO_LDFLAGS="$(CGO_LDFLAGS)" go $@ -mod=readonly -trimpath $(BUILD_FLAGS) $(BUILDARGS) ./cmd/...

# ensure build directory exists
$(BUILDDIR)/:
	mkdir -p $(BUILDDIR)/

go.sum: go.mod
	@echo "--> Ensure dependencies have not been modified"
	@go mod verify

.PHONY: build install
