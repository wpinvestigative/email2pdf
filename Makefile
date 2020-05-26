TEMPDIR := $(shell mktemp -t tmp.XXXXXX -d)
FLAKE8 := $(shell which flake8)
UNAME := $(shell uname)
DOCKERTAG = andrewferrier/email2pdf

determineversion:
	$(eval GITDESCRIBE := $(shell git describe --dirty))
	sed 's/Version: .*/Version: $(GITDESCRIBE)/' debian/DEBIAN/control_template > debian/DEBIAN/control
	$(eval GITDESCRIBE_ABBREV := $(shell git describe --abbrev=0))
	sed 's/pkgver=X/pkgver=$(GITDESCRIBE_ABBREV)/' PKGBUILD_template > PKGBUILD

ifeq ($(UNAME),Linux)
builddeb: determineversion builddeb_real
else
builddeb: rundocker_getdebs
endif

builddeb_real:
	sudo apt-get install build-essential
	cp -R debian/DEBIAN/ $(TEMPDIR)
	mkdir -p $(TEMPDIR)/usr/bin
	mkdir -p $(TEMPDIR)/usr/share/doc/email2pdf
	cp email2pdf $(TEMPDIR)/usr/bin
	cp README* $(TEMPDIR)/usr/share/doc/email2pdf
	cp LICENSE* $(TEMPDIR)/usr/share/doc/email2pdf
	cp getmailrc.sample $(TEMPDIR)/usr/share/doc/email2pdf
	sudo chmod -R u=rwX,go=rX $(TEMPDIR)
	sudo chmod -R u+x $(TEMPDIR)/usr/bin
	sudo dpkg-deb --build $(TEMPDIR) .

buildarch: determineversion
	makepkg --skipinteg

builddocker: determineversion
	docker build -t $(DOCKERTAG) .
	docker tag $(DOCKERTAG):latest $(DOCKERTAG):$(GITDESCRIBE)

builddocker_nocache: determineversion
	docker build --no-cache -t $(DOCKERTAG) .
	docker tag $(DOCKERTAG):latest $(DOCKERTAG):$(GITDESCRIBE)

rundocker_interactive: builddocker
	docker run --rm -i -t $(DOCKERTAG) bash -l

rundocker_testing: builddocker
	docker run --rm -t $(DOCKERTAG) bash -c 'cd /tmp/email2pdf && make unittest && make stylecheck'

rundocker_getdebs: builddocker
	docker run --rm -v ${PWD}:/debs $(DOCKERTAG) sh -c 'cp /tmp/*.deb /debs'

unittest:
	python3 -m unittest discover

unittest_verbose:
	python3 -m unittest discover -f -v

analysis:
	# Debian version is badly packaged, make sure we are using Python 3.
	-/usr/bin/env python3 $(FLAKE8) --max-line-length=132 email2pdf tests/
	pylint -r n --disable=line-too-long --disable=missing-docstring --disable=locally-disabled email2pdf tests/

coverage:
	rm -rf cover/
	nosetests tests/Direct/*.py --with-coverage --cover-package=email2pdf,tests --cover-erase --cover-html --cover-branches
	open cover/index.html

.email2pdf.profile: email2pdf
	python3 -m cProfile -o .email2pdf.profile `which nosetests` .

profile: .email2pdf.profile
	python3 performance/printstats.py | less

alltests: unittest analysis coverage

ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
SOURCE_DIR=$(HOME)
TMP_DIR=/tmp
OUTPUT_DIR=$(ROOT_DIR)

/tmp/emails:
	@mkdir -p $(TMP_DIR)/emails
	@echo "moving files to tmp"
	@find $(SOURCE_DIR) -name "*.msg" -exec mv {} $(TMP_DIR)/emails \;

INPUT_DIR=$(TMP_DIR)/emails
pdfs:
	@mkdir -p $(OUTPUT_DIR)
	@echo "converting to pdf"
	@find $(INPUT_DIR) -iname "*\.msg" \
	| xargs basename \
	| xargs -I% \
		./email2pdf \
			--input-encoding ISO-8859-1 \
			-i $(INPUT_DIR)/"%" \
			-o $(OUTPUT_DIR)/"%.pdf"
