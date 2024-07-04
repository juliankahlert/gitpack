PREFIX ?= /usr/local

.PHONY: all install

all:
	@echo "Nothing to do"

install: gitpack
	install -d $(PREFIX)/bin
	install -d /etc/bash_completion.d
	install -m 755 gitpack $(PREFIX)/bin
	install -m 755 gitpack.bash_completion /etc/bash_completion.d/gitpack
