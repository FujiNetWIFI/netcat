# Makefile -- netcat for the Odyssey 2: build/nc.bin (see build.sh).
# Standalone, like intv/ and astrocade/: not part of the root mekkogx build.
#   make                       the image, dialling the default
#   make ENDPOINT=N:TCP://host:port/
#   make spike                 the display engine's test pattern
#   make test                  tools/termtest.py: test/scen against a fixture
ENDPOINT ?= N:TELNET://bbs.retrocampus.com/

all:
	ENDPOINT='$(ENDPOINT)' ./build.sh

spike:
	SPIKE=1 OUT=build/spike ./build.sh

test:
	python3 tools/termtest.py

clean:
	rm -rf build

.PHONY: all spike test clean
