#!/bin/bash

# Rebuild the site, and if any files are written reindex
# This is expected to be run as a cron job

if test ! -n "$1"; then
    echo "Must specify path to the root of the site (e.g. $HOME)"
    exit 1
fi

# Directory where everything happens
ROOT="$1"
shift;


SVN="$ROOT/swish_website"


# Where to store output from svn 
TMP=/tmp/swish_website.$$.tmp


# First try and do a svn update

cd $SVN

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



SWISH_SITE=${SWISH_SITE:=http://swish-e.org}
SPIDER_QUIET=${SPIDER_QUIET:=1}

export SPIDER_QUIET SWISH_SITE

# Now build the website, if any -a passed or if "Updated to revision" is returned.
# Or perhaps could just check for (A|C|D|U|G)

if [ -n "$(echo $@ | grep -- '-a')"  ] || egrep '^Updated to revision' $TMP >/dev/null; then
    echo "updating site"

    $SVN/bin/build --root $ROOT $@ \
    && swish-e \
        -c $SVN/etc/swish.config \
        -S prog \
        -f $ROOT/indexes/index.swish-e \
        -v 0
fi


rm $TMP
