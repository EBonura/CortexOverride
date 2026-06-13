# run the current build:  make run
# pico-8 resolves from PATH by default. for a non-standard
# install, put your path in local.mk (gitignored), e.g.:
#   PICO8 = /path/to/pico8
# or override per-invocation: make run PICO8=/path/to/pico8
-include local.mk
PICO8 ?= pico8
CART ?= v0.3.2.p8

run:
	$(PICO8) -run $(CART)

export:
	zip archive.zip index.js index.html
	mv archive.zip ~/Desktop
