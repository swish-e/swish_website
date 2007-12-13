#!/usr/bin/env perl
use warnings;
use strict;
use Getopt::Long;
use Data::Dumper;
use Pod::Usage;
use File::Basename;
use Cwd;
use IO::Handle;

# Script to build swish-e from svn (or LWP request tarball)
# Normally used for the daily builds of the tarball

# WARNING -- commands are run through the shell.

#--------------- config ---------------------------------------------

my %config = (
        svnco           => 'svn co http://svn.swish-e.org/swish-e/trunk/',
        tar_keep_days   => 15,  # number of days to keep tarfiles
        build_keep_days => 2,   # number of days to keep previous build
        timestamp       => 1,   # build swish with a timestamp
        remove          => 1,   # remove tar and build dirs
        logs            => 1,   # write log files
        symlink         => 1,   # create symlink
        srpm           => 1,   # build srpms
);

#--------------------------------------------------------------------


GetOptions( \%config,
    qw/
       topdir=s
       tardir=s
       tar_keep_days=i
       build_keep_days=i
       svnco=s
       dump
       verbose
       timestamp!
       fetchtarurl=s
       remove!
       logs!
       symlink!
       srpm!
       help man options
       config_options=s
    /
) or pod2usage(
    {
        -verbose => 0,
        -exitval => 1,
    } );

# Set dependent variables and select new day_dir that doesn't already exist
set_dependent_vars( \%config );

if ( $config{dump} ) {
    print STDERR Dumper \%config;
    exit;
}

my @functions = (
    [ \&svn_checkout, 'Check out from svn' ],  # can be replaced by a LWP fetch with --fetchtarurl=<url>
    [ \&configure,    'Run configure' ],
    [ \&make_install, 'Run make install' ],
    [ \&make_dist,    "Run make dist and move tarball to $config{tardir}"  ],
    [ \&make_src_rpm, "Build swish-e .src.rpm" ],
    [ \&set_symlink,  "Make symlink $config{symlink} point to $config{day_dir}" ],
    [ \&remove_day_dir, "Remove old install and build directories" ],
);



pod2usage( {
    -verbose => ($config{man} ? 2 : $config{options} ? 1 : 0),
    -exitval => 1,
   } ) if $config{man} || $config{help} || $config{options};


# replace svn co with a LWP fetch?
$functions[0] = [ \&fetch_tar_url, 'Fetch tarball' ] if $config{fetchtarurl};

# Move to the toplevel directory
unless ( chdir $config{topdir} ) {
        warn "Failed to chdir to $config{topdir}: $!";
        # Try to create the directory
        mkdir $config{topdir},0777 || die "Failed to mkdir topdir $config{topdir}: $!";
        warn "Created top level directory $config{topdir}\n";
        chdir $config{topdir} || die "Failed to chdir to $config{topdir}";
}


# Create needed directories
#
mkdir $config{day_dir} || die "Failed to create the working day directory '$config{day_dir}': $!\n";


# This has got to go



# Open the log files.
if ( $config{logs} ) {
    open STDOUT, ">$config{buildlog}" or die "Failed to open build log file '$config{buildlog}': $!\n";
    open STDERR, ">$config{errorlog}" or die "Failed to open error log file '$config{errorlog}': $!\n";

    # Since forking off sub-processes
    STDERR->autoflush(1);
    STDOUT->autoflush(1);
}





for my $step ( @functions ) {
    next if $step->[2];  # skip from above
    log_message( $step->[1] );
    $step->[0]->(\%config) || exit_with_error( \%config );
}
exit 0;




#=====================================================================
# Checkout in the source code from svn.

sub svn_checkout {
    my $c = shift;

    run_command( "$c->{svnco}  $c->{srcdir}" );
}



#=======================================================================
# Runs configure *in* the build directory
# There's no requirement to configure and build from the directory
# where the source is located on most platforms, and maybe it would
# be good in the future to have separate source and build dirs.

sub configure {
    my $c = shift;
    my $options = $c->{config_options} || '';

    mkdir $c->{builddir} || die "Failed to mkdir $c->{builddir}: $!\n";
    chdir $c->{builddir} || die "Failed to chdir $c->{builddir}: $!";
    log_message( "Changed to build directory: $c->{builddir}" );



    my $timestamp = $c->{timestamp} ? '--enable-daystamp'  : '';
    my $command = "$c->{srcdir}/configure $timestamp $options --prefix=$c->{installdir} $options";
    run_command( $command );
}

#=======================================================================
# make_src_rpm( $c )
# makes a .src.rpm from the source tree 
#  by setting up a rpmbuild environment and creating a special
#  rpmrc file for rpmbuild.
#  The version for rpm must look like '2.5.6', and we set
#  the release of the rpm to the svn revision number.
#  (This will need to be revisited for release .src.rpms)
#
# The .src.rpm is deposited into $builddir/rpmbuild/SRPMS
#
#  Building .src.rpm can be tested with:
#     % mkdir -p /tmp/swish_daily_build /tmp/swish-daily;
#     % ./swish-daily.pl -topdir /tmp/swish_daily_build/ -tardir /tmp/swish-daily -v -nolog
sub make_src_rpm {
    my $c = shift;

    return 1 unless $c->{srpm};

    my ($rpmbuilddir, $rpmrcfile) = setup_rpmbuild_environment( $c );
    my $tarball  = "$c->{tardir}/swish-e-$c->{version}.tar.gz"; # this should be factored out
    my $srcdir   = $c->{srcdir};  
    my $builddir = $c->{builddir};  
    my $specversion = $c->{version};

    # if we're in --timestamp mode, then we need to make sure that the tarball
    # unpacks into EG: swish-e-2.5.6, and not swish-e-2.5.6-2007-12-12
    if ($config{timestamp}) {

        my $origspecversion = $specversion;
        $specversion =~ s/-.*//;   # remove all after and including the hyphen from 2.5.6-2007-12-12
                                   # IE, from 2.5.6-2007-12-08 to 2.5.6 

        my $newtarball = $tarball;
        $newtarball  =~ s/-\d+-\d+-\d+\.tar.gz$/.tar.gz/;  # remove -2007-12-12 from tarball

        die "$0: failed to figure out name of new tarball for .src.rpm\n" 
            unless ($newtarball ne $tarball);

        # create a new tarball that extacts to the right dirname, and set $tarball to it
        _rewrite_tarball( $c, $tarball, $newtarball, "swish-e-$origspecversion", "swish-e-$specversion" ); 
        $tarball = $newtarball;
    }

    run_command( "cp $tarball                   $rpmbuilddir/SOURCES/swish-e-$specversion.tar.gz" );
    run_command( "cp $srcdir/rpm/swish-e.xpm    $rpmbuilddir/SOURCES" );
    run_command( "cp $builddir/rpm/swish-e.spec $rpmbuilddir/SPECS" );

    # fixup the version string in the .spec file, IE, from 2.5.6-2007-12-08 to 2.5.6 
    # also change the release string to our new specrelease if in timestamp mode
    _apply_regexes( "$rpmbuilddir/SPECS/swish-e.spec", 
                          qq{s/^%define[[:space:]]+version.*/%define version $specversion/ims} ); 

    # also, if in timestamp mode, change the specrelease to be YYYYMMDD
    if ($config{timestamp}) {
        chomp(my $specrelease = `date '+%Y%m%d'`);  # normally this is a 1-2 digits
        _apply_regexes( "$rpmbuilddir/SPECS/swish-e.spec", 
            qq{s/^%define[[:space:]]+release.*/%define release $specrelease/ims} );
    } 

    # build the new .src.rpm using our rpmrcfile and swish-e.spec
    # (and all the stuff in $builddir/rpmbuild/)
    run_command( "rpmbuild --rcfile=$rpmrcfile -bs $rpmbuilddir/SPECS/swish-e.spec" );

    log_message( "new .src.rpm build in $rpmbuilddir/SRPMS" );
}

#=======================================================================
# setup_rpmbuild_environment( $c )
# sets up an rpmbuild environment and returns the rpmbuilddir
#  creates the directories RPMS SOURCES SPECS SRPMS BUILD in ./rpmbuild,
#  and creates an rpmrc file that uses our .rpmmacros file
#  in order to use our rpmbuild environment.
# returns (fullpath to ./rpmbuild, rpmrc file)
sub setup_rpmbuild_environment {
    my $c = shift;
    # we'll assume we're in $c->{builddir}
    my $cwd = getcwd();
    print "debug: cwd is $cwd\n";

    # where the whole rpmbuild tree goes
    my $rpmbuilddir = "$cwd/rpmbuild/";

    # make the subdirs needed by rpmbuild
    for my $dir (qw(  RPMS SOURCES SPECS SRPMS BUILD ) ) {
        system( "mkdir -p $rpmbuilddir/$dir" ) unless -d $dir;
    }

    # write our rpmmacros file that informs rpmbuild of our rpmbuild tree
    my $rpmmacrosfile = "$cwd/.rpmmacros";
    log_message( "Creating new $rpmmacrosfile" );
    open(my $fh, ">", $rpmmacrosfile) || die "$0: Failed to open $rpmmacrosfile: $!";
    print $fh "%_topdir $rpmbuilddir\n";
    print $fh "%make    make\n";
    close($fh) || die "$0: Failed to close $rpmmacrosfile: $!";

    # write our rpmrc file that gets rpmbuild to use our special $rpmmacros file
    my $rpmrcfile = "$rpmbuilddir/rpmrc";
    log_message( "Creating new $rpmrcfile" );
    run_command( "cp /usr/lib/rpm/rpmrc $rpmrcfile" );
    _apply_regexes( $rpmrcfile, q{s!^(macrofiles:.*)!$1:./.rpmmacros!ims} );   # append ./.rpmmacros

    return ($rpmbuilddir, $rpmrcfile);
}


#=======================================================================
# This does a make-install to do everything...


sub make_install {
    my $c = shift;

    chdir $c->{builddir} || die "Failed to chdir $c->{builddir}: $!";
    log_message( "Changed to build directory: $c->{builddir}" );

    run_command( "make" ) || return;
    run_command( "make test" ) || return;
    run_command( "make install" ) || return;

    unless ( -d $c->{installdir} ) {
        warn "Did not find install directory $c->{installdir} after make install";
        return;
    }

    # check binary and fetch version

    my $binary = "$c->{installdir}/bin/swish-e";
    die "Failed to find swish-e binary $binary: $!\n" unless -x $binary;
    my $version = `$binary -V`;
    chomp $version;
    if ( $version =~ /^SWISH-E\s+(.+)$/ ) {
        $c->{version} = $1;
    }
    return 1;
}


#=========================================================================
# This function builds a tarball and copies it to the tardir


sub make_dist {
    my $c = shift;

    chdir $c->{builddir} || die "Failed to chdir $c->{builddir}: $!";
    log_message( "Changed to build directory: $c->{builddir}" );

    run_command( "make dist" ) || return;

    unless ( $config{tardir} ) {
        log_message( "tardir option not given -- not moving tarball." );
        return 1;
    }



    # Copy to tardir and create a symlink for "latest.tar.gz"

    # Do we know the version?

    if ( $c->{version} && -e "swish-e-$c->{version}.tar.gz") {

        # Move to the tar directory and create a symlink for "latest.tar.gz"

        my $latest = "$c->{tardir}/latest.tar.gz";

        run_command( "mv swish-e-$c->{version}.tar.gz $c->{tardir}" );

        run_command( "rm -f $latest" );
        run_command( "ln -s $c->{tardir}/swish-e-$c->{version}.tar.gz $latest");

    } else {
        log_message( "Found swish version [$c->{version}] but didn't find [swish-e-$c->{version}.tar.gz]" )
            if $c->{version};
    }

    # purge old ones
    purge_old_tarballs( $c ) if $c->{remove};

    return 1;
}

sub purge_old_tarballs {
    my $c = shift;
    opendir( DIR, $c->{tardir} ) || die "Failed to open tardir: $!";

    my $days = $c->{tar_keep_days} || 10;
    my $old = time - ( 60 * 60 * 24 * $days );

    my @deletes;
    while ( my $file = readdir( DIR ) ) {
        next unless $file =~ /^swish-e.*\.tar\.gz$/;
        next if (stat "$c->{tardir}/$file")[9] > $old;
        push @deletes, "$c->{tardir}/$file";
    }


    for ( @deletes ) {
        print unlink( $_ )
                ? "Deleted old tar file '$_'\n"
                : "Failed to delete old tar '$_': $!\n";
    }

    return 1;

}




#===================================================================================
# Set symlink to point to this directory

sub set_symlink {
    my $c = shift;

    return 1 unless $c->{symlink};

    run_command( "rm -f $c->{symlink}" );
    run_command( "ln -s $c->{day_dir} $c->{symlink}" );
}


#===================================================================================
# Remove old day_dirs  (build directories)


sub remove_day_dir {
    my $c = shift;
    return 1 unless $c->{remove};

    my $days = $c->{build_keep_days} || 2;
    my $old = time - ( 60 * 60 * 24 * $days );

    opendir DIR, $c->{topdir} or die "Failed to open topdir '$c->{topdir}' for reading: $!\n";
    my @dirs = grep {
        /^swish-e-\d\d\d\d-\d+-\d+/ &&
        -d "$c->{topdir}/$_" &&
        (stat "$c->{topdir}/$_")[9] < $old
    } readdir( DIR );
    close DIR;

    return 1 unless @dirs;

    run_command( "rm -rf $c->{topdir}/$_" ) for @dirs;

    return 1;
}




#=============================================================
# Run a command and log the command being run


sub run_command {
    my $command = shift;
    log_message( $command );

    #return !system( $command );
    system( $command ) && die "$0: Command failed: $command: $!";
    return 1;
}

#=============================================================
# Write a message with a timestamp to stdout

sub log_message {
    my $command = shift;
    print "\n", scalar localtime,"\n $command\n\n";
}


#=============================================================
# write a message to stderr and die.

sub exit_with_error {
    my $c = shift;
    print STDERR `cat $c->{errorlog}` if -e $c->{errorlog};
    die "aborted $0\n";
}


#================================================================
# Set initial variables and stuff like that...


sub set_dependent_vars {
    my $config = shift;

    # Set the topdir as the current directory if not set
    # and make it absolute
    $config->{topdir} ||= getcwd;
    $config->{topdir} = Cwd::abs_path( $config->{topdir} );
    die "Failed to set 'topdir' - perhaps invalid directory: $!\n" unless $config->{topdir};


    # check for a tardir

    $config->{tardir} ||= '';

    if ( $config->{tardir} ) {
        $config->{tardir} = Cwd::abs_path( $config->{tardir} );

        die "Invalid tardir specified\n" unless defined $config->{tardir};
        die "tardir directory of $config->{tardir} does not exist\n" unless -e $config->{tardir};
        die "tardir option of $config->{tardir} is not a directory\n" unless -d $config->{tardir};
        die "tardir directory of $config->{tardir} is not writable\n" unless -w $config->{tardir};
    }



    my ($d,$m,$y) = (localtime)[3,4,5];
    my $today = sprintf('%04d-%02d-%02d', $y+1900, $m+1, $d );

    my $day_dir = "$config->{topdir}/swish-e-$today";


    # Now try and make that directory
    if ( -d $day_dir ) {
        my $count;
        1 while $count++ < 100 && -e "$day_dir.$count";
        $day_dir = "$day_dir.$count";
    }

    $config->{day_dir}      = $day_dir;
    $config->{symlink}      = "$config->{topdir}/latest_swish_build" if $config->{symlink};
    $config->{builddir}     = "$day_dir/build";
    $config->{srcdir}       = "$day_dir/source";
    $config->{installdir}   = "$day_dir/install";

    $config->{buildlog}     = "$day_dir/build.log";
    $config->{errorlog}     = "$day_dir/error.log";


}

#====================================================================
# Fetch a tarball and unpack into build directory.  Hopefully.
# Tries to figure out the source directory

sub fetch_tar_url {
    my $config = shift;

    chdir $config->{day_dir} || die "Failed to chdir to $config->{day_dir}\n";

    require LWP::Simple;
    require URI;

    log_message( "Fetching $config->{fetchtarurl}");

    my $u = URI->new( $config->{fetchtarurl} ) || die "$config->{fetchtarurl} doesn't look like a URL: $!";

    my ( $name, $path, $suffix ) = fileparse( $u->path, qr/\.tar\.gz/ );

    die "Failed to parse $config->{fetchtarurl} [$path $name $suffix]\n"
       unless $path && $name && $suffix;

    my $tar = $name . $suffix;

    my $status = LWP::Simple::getstore( $config->{fetchtarurl}, $tar ) || die "Failed to fetch $config->{fetchtarurl}";
    die "fetching $config->{fetchtarurl} returned a status of $status" unless $status == 200;

    die "Can't find fetched file $tar" unless -e $tar;


    run_command( "gzip -dc $tar | tar xvf -" ) || return;

    # see if the tar name is indeed the install directory
    unless ( -d $name ) {
        # ok, try and get from the tar
        open( TAR, "gzip -dc $tar | tar tf -|") or die "Failed to pipe from tar:$!";
        $name = '';
        while ( <TAR> ) {
            chomp;
            if ( m!^(.+?)/! && -d "$config->{day_dir}/$1" ) {
                $name = $1;
                last;
            }
        }
        close TAR;
    }


    die "Failed to find source directory after unpacking $tar" unless $name;

    # Create a symlink to the source directory

    run_command( "ln -s $config->{day_dir}/$name $config->{srcdir}");

    return 1;

}

#================================================================
# _apply_regexes( $file, @search_and_replace_regexes )
# backs up $file to $file.bak, and 
# applies supplied regexes to the lines of a file,
sub _apply_regexes {
    my ($file, @regexes) = @_;
    # changes a file by applying the supplied regexes to each line
    my $tmpfile = "$file.tmp";
    open(my $rfh, "<", $file)    || die "$0: Can't open $file: $!";
    open(my $wfh, ">", $tmpfile) || die "$0: Can't open $tmpfile: $!";  # clobber old $file.tmp
    print "Applying regexes:to file $file\n" . join("\n", @regexes) . "\n";
    while(<$rfh>) {
        chomp();
        for my $r (@regexes) {
            # $r should operate on $_ !
            eval $r;  
            die "$0: Error in regex: $r: $@" if $@;
        }
        print $wfh "$_\n";
    }
    close($rfh) || die "$0: Can't open $file: $!";
    close($wfh) || die "$0: Can't close $tmpfile: $!";
    rename( $file, "$file.bak" );
    rename( $tmpfile, $file ) || die "$0: Can't rename $tmpfile to $file: $!";
}

#================================================================
# my $newtarball = _rewrite_tarball( $fromtarball, $totarball, $fromdir, $todir )
#  creates a new tarball from $tarball that extracts into $todir instead of $fromdir
sub _rewrite_tarball {
    my ($c, $fromtarball, $totarball, $fromdir, $todir) = @_;
    my $builddir = $c->{builddir};  
    my $cwd = getcwd();

    #warn "$0: rewriting $fromtarball to $totarball,\n$0 to extract into $todir, not $fromdir\n$0: Currently in $cwd\n"; 
    
    # create and cd into our tmp dir
    mkdir( "$builddir/tmp" ) || die "$0: Couldn't create $builddir/tmp";
    chdir( "$builddir/tmp" ) || die "$0: Couldn't cd into $builddir/tmp";

    # uncompress and recompress the tarball with a different dir name.
    run_command( "tar -zxf $fromtarball" );
    die "$0: tarball didn't extract into $fromdir\n" unless -d $fromdir;
    run_command( "mv $fromdir $todir" );
    run_command( "tar -zcf $totarball $todir" );

    # go back to the right directory.
    chdir( $cwd ) || die "$0: Couldn't cd into $cwd";
}

__END__

=head1 NAME

swish-daily.pl - Builds a daily snapshot of swish from svn or tarball

=head1 SYNOPSIS

./swish-daily.pl [options]

Options:

    -help                   brief help
    -man                    longer help
    -options                list options
    -dump                   dump configuration and exit.  Good for seeing defaults
    -ask                    ask what tasks to run
    -tardir=<path>          where to place tarball when finished
    -tar_keep_days=<int>    number of days to keep old tarballs (default 15 days)
    -build_keep_days=<int>  number of days to key old build directories (default 2 days)
    -svnco=<string>         command to checkout from svn
    -fetchtarurl=<url>      specify a URL to a tarball to fetch (instead of using svn)
    -[no]timestamp          if set will create tarball with a timestamp (default is timestamp)
    -[no]remove             remove old tar files or old build directories (default yes)
    -[no]symlink            create symlink pointing to created directory
    -[no]logs               don't create build and error log files



    mkdir tardir
    swish-daily.pl \
        -svnco='http://svn.swish-e.org/swish-e/trunk/' \
        -tardir=tardir


=head1 DESCRIPTION

This script fetches the swish-e source, either from svn or from a URL, builds
swish and creates a tarball.  The script is mostly used for building daily builds,
but is also used when creating a new release of swish-e.

A build directory is created (using the date and a sequence number).  This directory is
created under the current directory, or under the directory specified by the topdir option.
So, either chdir to a top-level build directory or use the -topdir option.

Swish is then checked out via subversion (or from a tarball from the web using the
-fetchtarurl option) into a "source" directory.  Swish-e is then built from the "build"
directory and installed into the "install" directory.  Log files "build.log" and
"error.log" are also created (unless disabled with -nologs option).

A tarball is built and copied to the tar directory if "tardir" is specified.  Old
tar files will be purged (based on tar_keep_days option).

If all goes well a symlink is created in the topdir pointing to the latest build directory.
This symlink can be used to link to the latest version of the HTML docs and to the error
and build log files.

Finally, old build directories are removed (based on build_keep_days option).

=head2 Building HTML documentation

The swish-e configure script

=head2 Examples

A daily script might use:

    swish-daily.pl \
        --topdir=$HOME/swish_daily_build \\
        --tardir=$HOME/swish-daily

Which creates a directory structure like:

    $ ls -l swish_daily_build/
    latest_swish_build -> swish-e-2005-05-29
    swish-e-2005-05-26
    swish-e-2005-05-27
    swish-e-2005-05-28
    swish-e-2005-05-29


When building a release:

    swish-daily.pl \
        --fetchtarurl=<some url>
        --topdir=$HOME/swish_release_build \
        --tardir=$HOME/swish-releases \
        --noremove \
        --notimestamp \

Use --noremove to avoid purging old builds, and --notimestamp to prevent adding a time
stamp to the version (which is done when creating the daily builds).


=head1 OPTIONS

=over 8

=item B<-dump>

This dumps the configuration and exits.  Use to see what paths are going to be used.

=item B<-tardir>

This is a directory where the finished tarball will be placed.  Old tar files
(older than -tar_keep_days old) will be removed.  The default is 15 days.
If not specified then tarfile will not be moved.

=item B<-svnco>

String for checking out from svn.  Run -dump to see an example.

=item B<-fetchtarurl>

Specifies a URL where to fetch the tarball.  This will replace the use of svn for fetching the source.


=item B<-[no]timestamp>

This is set by default and causes the tarball to be build with a day stamp.  Use -notimestamp
to build without a timestamp.  (Sets --enable-daystamp in configure).

=item B<-[no]romove>

Normally the build directory and the last installation directory (from a previous run)
are removed when done.  This prevents this.

=item B<-[no]symlink>

Update the symlink pointing to the latest build directory.  Default is to update the
symlink

=item B<-tar_keep_days>

Number of days to keep old tarfiles around (must speicify -tardir).  Default is 15.

=item B<-build_keep_days>

Number of days to keep old build directories around.  Build dirs are directories
located in -topdir that match a given pattern.

=item B<-[no]logs>

Create build and error logs -- stdout and stderr are not redirectied.
The default is to create the log files.

=head1 CRON

Here's an example of a cron entry:

  55 1 * * * . $HOME/.bashrc && $HOME/swish-daily.pl --tardir=$HOME/swish-daily --topdir=$HOME/swish_daily_build || echo "Check Swish Daily Build"

=head1 COPYRIGHT

This library is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.


=head1 AUTHOR

Bill Moseley moseley@hank.org. 2002/2003/2004

=head1 SUPPORT

Please contact the Swish-e discussion email list for support with this module
or with Swish-e.  Please do not contact the developers directly.


=cut
