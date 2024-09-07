PREFIX ?= /usr/local

.PHONY: all install

all:
	@echo "Nothing to do"

install: gitpack.rb
	install -d $(PREFIX)/bin
	install -d /etc/bash_completion.d
	install -m 755 -T gitpack.rb $(PREFIX)/bin/gitpack
	install -m 755 gitpack.bash_completion /etc/bash_completion.d/gitpack
