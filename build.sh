#!/bin/bash

# Rebuild the site, and if any files are written reindex
# This is expected to be run as a cron job
# cd to the swish_website dir then run this script


# Directory where everything happens
WEB_ROOT="$(pwd)/.."


# Path to the archive index file -- so search script can find the index.
ARCHIVE_INDEX="$WEB_ROOT/swish/search/index.swish-e"

# Path to swish-e source to find pods for building the docs
SWISH_SRC="$WEB_ROOT/swish_src"

# Path to the daily build soruce to build the dev docs
DEV_SRC="$WEB_ROOT/devel_src"


SWISH_SITE=http://swish-e.org
SPIDER_QUIET=1
export SWISH_SITE SPIDER_QUIET


# Where to store output from svn 
TMP=tmp/swish_website.$$.tmp


# First try and do a svn update

if ! svn update &>$TMP; then
    echo "svn update failed"
    echo
    cat $TMP; rm $TMP
    exit
fi

# Look out for any local problems
#    A  Added
#    D  Deleted
#    U  Updated
#    C  Conflict
#    G  Merged

# Check for conflicts -- which should not happen
# unless messing with the source locally

if egrep '^C ' $TMP >/dev/null; then
    echo "Some files need attention"
    echo
    cat $TMP
    rm  $TMP
    exit
fi


# Now build the website, if any -a passed or if "Updated to revision" is returned.
# Or perhaps could just check for (A|C|D|U|G)

if [ -n "$(echo $@ | grep -- '-a')"  ] || egrep '^Updated to revision' $TMP >/dev/null; then
    echo "updating site"
    bin/build \
        -archive=$ARCHIVE_INDEX \
        -swishsrc=$SWISH_SRC \
        -develsrc=$DEV_SRC \
        $@ \
    && swish-e -c etc/swish.config -S prog -v 0
fi



rm $TMP
