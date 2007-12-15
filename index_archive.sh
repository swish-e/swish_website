#!/bin/sh

if test ! -n "$1"; then
    echo "Must specify path to the root of the site (e.g. $HOME)"
    exit 1
fi

ROOT="$1"

            $ROOT/swish_website/bin/index_hypermail.pl $ROOT/archive \
                | swish-e \
                    -S prog \
                    -i stdin \
                    -c $ROOT/swish_website/etc/archive.conf \
                    -f $ROOT/indexes/archive.swish-e \
                    -W0 \
                    -v0


