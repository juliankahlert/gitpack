PREFIX ?= /usr/local

.PHONY: all install

all:
	@echo "Nothing to do"

install: gitpack
	install -d $(PREFIX)/bin
	install -m 755 gitpack $(PREFIX)/bin
