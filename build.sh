#!/bin/bash

# Rebuild the site, and if any files are written reindex

SWISH_SITE=http://swish-e.org
SPIDER_QUIET=1
export SWISH_SITE SPIDER_QUIET

TMP=$HOME/swish_website.$$.tmp


if ! cvs -q update &>$TMP; then
    echo "cvs update failed"
    echo
    cat $TMP; rm $TMP
    exit
fi

# Look out for any local problems

if egrep '^(M|C|A|R) ' $TMP >/dev/null; then
    echo "Some files need attention"
    echo
    cat $TMP
    rm  $TMP
    exit
fi 


if [ -n "$(echo $@ | grep -- '-a')"  ] || egrep '^(U|P) ' $TMP >/dev/null; then
    echo "updating site"
    perl bin/build \
        -archive=$HOME/swish/search/index.swish-e \
        -swishsrc=swishsrc \
        -develsrc=develsrc $@ && swish-e -c etc/swish.config -S prog -v 0
fi

rm $TMP
