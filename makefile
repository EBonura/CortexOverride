# run the current build:  make run
# if pico-8 isn't on your PATH, override:
#   make run PICO8=/path/to/pico8
PICO8 ?= pico8
CART ?= v0.3.2.p8

run:
	$(PICO8) -run $(CART)

export:
	zip archive.zip index.js index.html
	mv archive.zip ~/Desktop
