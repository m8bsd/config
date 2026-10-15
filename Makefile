# Build the fbsd-config man page. Works with FreeBSD make and GNU make.

PAGE=	fbsd-config
SECT=	7
SRC=	${PAGE}.${SECT}
PREFIX?=	/usr/local
MANDIR?=	${PREFIX}/share/man/man${SECT}

all: ${PAGE}.txt ${PAGE}.html

${PAGE}.txt: ${SRC}
	mandoc -T utf8 ${SRC} | col -b > $@

${PAGE}.html: ${SRC}
	mandoc -T html -O style=style.css ${SRC} > $@

lint:
	mandoc -T lint ${SRC}

view:
	mandoc -T utf8 ${SRC} | less -R

install: ${SRC}
	install -d ${MANDIR}
	install -m 444 ${SRC} ${MANDIR}/

clean:
	rm -f ${PAGE}.txt ${PAGE}.html

.PHONY: all lint view install clean
