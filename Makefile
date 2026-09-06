# ws-cli — build and install the `ws` executable.

EXECUTABLE := ws
CONFIG     := release

# Where `make install` puts the binary. Override on the command line:
#   make install PREFIX=/usr/local     # system-wide, needs: sudo make install PREFIX=/usr/local
#   make install BINDIR=$$HOME/bin     # some other dir already on your PATH
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

.DEFAULT_GOAL := build

.PHONY: build
build: ## Compile the release binary
	swift build -c $(CONFIG) --product $(EXECUTABLE)

.PHONY: install
install: build ## Build, then copy the binary into BINDIR (default: ~/.local/bin)
	@bin_path="$$(swift build -c $(CONFIG) --show-bin-path)"; \
	install -d "$(BINDIR)"; \
	install -m 0755 "$$bin_path/$(EXECUTABLE)" "$(BINDIR)/$(EXECUTABLE)"; \
	echo "installed $(EXECUTABLE) -> $(BINDIR)/$(EXECUTABLE)"
	@case ":$$PATH:" in \
	  *":$(BINDIR):"*) ;; \
	  *) printf 'note: %s is not on your PATH. Add to ~/.zshrc:\n      export PATH="%s:$$PATH"\n' "$(BINDIR)" "$(BINDIR)" ;; \
	esac

.PHONY: uninstall
uninstall: ## Remove the installed binary
	rm -f "$(BINDIR)/$(EXECUTABLE)"
	@echo "removed $(BINDIR)/$(EXECUTABLE)"

.PHONY: clean
clean: ## Delete build artifacts
	swift package clean
	rm -rf .build

.PHONY: help
help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
