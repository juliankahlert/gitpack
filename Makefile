VERSION := $(shell ruby -e "puts Gem::Specification.load('gitpack.gemspec').version")
PREFIX ?= /usr/local

.PHONY: all install uninstall

all:
	@echo "Nothing to do"

install: bin/gitpack lib/gitpack.rb
	install -d /etc/bash_completion.d
	install -m 755 gitpack.bash_completion /etc/bash_completion.d/gitpack
	chmod +x bin/gitpack
	gem build
	gem install --local gitpack-$(VERSION).gem

uninstall:
	gem uninstall gitpack
	rm --recursive --force /etc/bash_completion.d/gitpack
