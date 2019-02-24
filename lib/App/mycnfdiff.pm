package App::mycnfdiff;
use strict;
use warnings;
use feature 'say';
use Data::Dumper;
use Text::CSV qw( csv );
use Cwd qw(getcwd);
use App::mycnfdiff::Utils qw(:all);
use Config::MySQL::Writer;
use File::Slurper qw(write_text);    # for writing diff
use File::Basename;
use File::Path qw(make_path);

=head1 NAME

App::mycnfdiff - compare MySQL server configs. 

Can also compare with mysqld compiled defaults (values after reading options)

=head1 SYNOPSIS
 
  $ mycnfdiff -d /foo/bar -l my.cnf.1,my.cnf.bak
  $ mycnfdiff -l server1/my.cnf,server2/my.cnf
  $ mycnfdiff -l 'exec:docker run -it percona mysqld --verbose --help,my.ini' -d /foo/bar
  $ mycnfdiff -s s2.ini,s3,ini  # read all cnf and ini files in current dir except s2.ini

Files must have .cnf or .ini extension otherwise they will not be parsed by default

To specify particular source without format restriction use -l option. 

If one of source is compiled defaults you can only use -l option

to-do: 

diff in csv format
  
=head1 DESCRIPTION

By default, it produce two output files

1) common.mycnfdiff with common options

2) diff.mycnfdiff with different options (hash style)

If utility can not write files it will print result to STDOUT and warn user about permissions

=head1 OPTIONS

For more info please check mycnfdiff --help

=cut

my $COMMON_FILENAME = 'my.cnf.mycnfdiff';
my $DIFF_FILENAME   = 'diff.txt.mycnfdiff';
my $COMPILED_PREFIX = 'exec:';
my $UNIQ_FOLDER = 'uniq';
my $SUGGEST_FOLDER = 'suggest';

# TO-DO: write compiled value(s) as comment
# TO-DO: sort params by name- https://github.com/rjbs/Config-INI/issues/11
sub _write_result {
    my ( $cmp_hash, $debug, $verbose ) = @_;
    Config::MySQL::Writer->write_file( $cmp_hash->{same}, $COMMON_FILENAME );
    say "write diff to $DIFF_FILENAME file in dumper format" if $verbose;
    write_text( $DIFF_FILENAME, Dumper $cmp_hash->{diff} ) if $debug;
}

sub run {
    my ( $self, $opts ) = @_;    # $opts is Getopt::Long::Descriptive::Opts

    my @sources = ( $opts->sources ? split( ',', $opts->sources ) : '.' );
    my @exclude      = ( $opts->exclude ? split( ',', $opts->exclude ) : () );
    my $dir_in = ( $opts->dir_in ? $opts->dir_in : '.' );
    my $dir_out = ( $opts->dir_out ? $opts->dir_out : '.' );
    
    if ( scalar @sources == 1 ) {
        say "Only one source specified, exiting";
        return;
    }
    
    # read source content into hash
    my $configs_content = get_configs(
        sources      => \@sources,
        exclude      => \@exclude,
        dir_in       => $dir_in,
        v            => $opts->verbose
    );

    my $full_cmp = split_compare_hash( compare($configs_content) );
    
    # Count how much compiled sources
    my $compiled_n = scalar grep { $_ =~ $COMPILED_PREFIX } keys %$configs_content;
    my $total_n = scalar keys %$configs_content;
    
    say "Total config parsed: ".$total_n.", compiled sources: ".$compiled_n if $opts->verbose;
    
    # Write end result if no compiled or just one uncompiled file.
    if ( ( $compiled_n == 0 ) || ( $total_n == $compiled_n + 1 ) ) {
        say "No compiled sources so writing final result" if ( $opts->verbose && ( $compiled_n == 0 ));
        say "Only one uncompiled source (no uncompiled sources to compare) so writing final result" if ( $opts->verbose && ( $total_n == $compiled_n + 1 ));
        _write_result($full_cmp, $opts->debug, $opts->verbose);
        return;
    }
    
    # Remove compiled and make comparision again
    my $compiled = {};
    for my $k ( keys %$configs_content) {
        if ( $k =~ $COMPILED_PREFIX ) {
            $compiled_n++;
            $compiled->{$k} = $configs_content->{$k};
            delete $configs_content->{$k};
        }
    }
    
    my $no_compiled_cmp;
    if ( ( $total_n != $compiled_n ) && ( scalar keys %$configs_content >= 2 ) ) {
        # since compare can work with minimum 2 configs
        $no_compiled_cmp = split_compare_hash( compare($configs_content) );
        _write_result($no_compiled_cmp, $opts->debug, $opts->verbose);
    }
    else {
        die "Can not get no_compiled_cmp";
    }
    
    say "Generate uniq configs, you can use them as defaults-extra-file" if $opts->verbose;
    make_path($UNIQ_FOLDER);
    
    # unless(mkdir $UNIQ_FOLDER) {
    #     die "Unable to create directory for uniq configs\n";
    # }
    
    my $result = process_diff ( $no_compiled_cmp->{diff} );
    
    for my $k ( keys %$result ) {
        Config::MySQL::Writer->write_file( $result->{$k}, $UNIQ_FOLDER.'/'.basename($k) );
    }
    
    # write 'suggestion' folder
    # add to # my.cnf
    if ( $compiled_n == 1 ) {
        
        say "Generate recommendation configs since you have only one compiled source" if $opts->verbose;
        
        make_path($SUGGEST_FOLDER);
        
        my ( $diff, $suggested_same ) = process_diff ( $no_compiled_cmp->{diff}, $compiled );
        
        for my $k ( keys %$diff ) {
            Config::MySQL::Writer->write_file( $diff->{$k}, $SUGGEST_FOLDER.'/'.basename($k) );
        }
        
        Config::MySQL::Writer->write_file( $suggested_same, $COMMON_FILENAME );
        
    }
    
    
}

1;
