#!/bin/sh

DIR=/opt/swish
SWISH_DAILY=$DIR/swish_website/bin/swish-daily.pl


############################################ 
# build the 2.4 branch
$SWISH_DAILY \
    --topdir=$DIR/swish_daily_build \
    --tardir=$DIR/swish-daily || (echo "swish 2.4 build failed" && exit 1);


############################################ 
# build the 2.6 branch (which makes 2.7.0 now)
# --no-latest  avoids making latest.tar.gz      symlink. 
# --no-symlink avoids making latest_swish_build symlink
$SWISH_DAILY \
    --svnco='svn co http://svn.swish-e.org/swish-e/branches/2.6/' \
    --bootstrap \
    --no-latest \
    --no-symlink \
    --topdir=$DIR/swish_daily_build \
    --tardir=$DIR/swish-daily || (echo "swish 2.6 build failed" && exit 1);


###########################################
# build libswish3
$SWISH_DAILY \
    --svnco='svn co http://svn.swish-e.org/libswish3/trunk' \
    --bootstrap \
    --no-latest \
    --no-symlink \
    --no-srpm \
    --topdir=$DIR/swish_daily_build \
    --tardir=$DIR/swish-daily || (echo "libswish3 build failed" && exit 1);

