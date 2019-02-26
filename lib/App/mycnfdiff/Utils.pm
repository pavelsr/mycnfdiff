package App::mycnfdiff::Utils;

# ABSTRACT: Common and reusable functions

use strict;
use warnings;
use feature 'say';
use experimental 'smartmatch';
use Carp;
use File::Spec::Functions qw/file_name_is_absolute splitdir catfile/;
use List::Compare;
use List::Util qw(uniq all notall);
use Config::MySQL::Reader;

use Data::Dump qw(dd);
use Data::Dumper;

use Const::Fast;
const my $ALLOWED_EXTENSIONS_REGEX => qr/\.ini|cnf$/;
const my $NO_PARAM_MSG             => 'EMPTY';
const my $COMPILED_PREFIX          => 'exec:';

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
  get_folder
  get_configs
  get_compiled_param
  get_all_group_prms
  compare
  split_compare_hash
  process_diff
  find_keys_by_val
  cmp_w_defaults
  _match
  _can_same_path
  _try_group_hash
);
our %EXPORT_TAGS = ( 'all' => [@EXPORT_OK] );

#Process skip files, filter extensions and return pwd-ed path
# Params: dir, skip, include_only
# Return list of files in dir

sub get_folder {
    my (%opts) = @_;

    my @exclude = @{ $opts{'exclude'} } if $opts{'exclude'};
    my $dir     = $opts{'dir'};

    say "Inspecting modules in " . $dir if $opts{'v'};
    say "Skip files : " . join( ',', @exclude )
      if ( $opts{'v'} && @exclude );

    my @files;
    opendir( my $dh, $dir ) or die $!;
    while ( my $file = readdir($dh) ) {

        # warn $file;
        next unless ( -f $dir . '/' . $file );
        next unless ( $file =~ m/$ALLOWED_EXTENSIONS_REGEX/ );
        push @files, $dir . '/' . $file;
    }
    closedir($dh);

    my $lc = List::Compare->new( \@files, \@exclude );
    return $lc->get_Lonly;
}

sub get_all_group_prms {
    my ( $hash, $group ) = @_;
    my @res;
    for my $k ( keys %$hash ) {
        push @res, keys %{ $hash->{$k}{$group} };
    }

    # for (@res) {
    #     $_ =~ s/-/_/g;
    # }
    return [ sort { $a cmp $b } uniq @res ];
}

=head1 get_configs

Get content of specified configs into hash using L<Config::MySQL::Reader>

Resolve `exec:` tag in case of compiled defaults source using get_cd()

=cut

sub get_configs {
    my (%opts) = @_;

    my $result = {};
    my @compiled_to_analyse;

    for my $source ( @{ $opts{'sources'} } ) {

        if ( $source =~ /$COMPILED_PREFIX/ ) { # detect_compiled_defaults_format
            my $cmd = ( split( /:/, $source ) )[1];    # extract command
            say "Executing external mysqld --verbose --help command : " . $cmd
              if $opts{'v'};
            my $content = [ split( '\n', `$cmd` ) ];
            push @compiled_to_analyse,
              { source => $source, content => $content };
        }
        elsif ( -d $source ) {
            say "Parsing directory $source" if $opts{'v'};
            my $file_list = get_folder(%opts);
            for my $f (@$file_list) {
                my $fpath = catfile( $source, $f );
                $result->{$fpath} = Config::MySQL::Reader->read_file($fpath);
            }
        }
        else {
            $source = catfile( $opts{'dir_in'}, $source ) if $opts{'dir_in'};
            $result->{$source} = Config::MySQL::Reader->read_file($source);
            say "Parsing $source, groups total : " . scalar
              keys %{ $result->{$source} }
              if $opts{'v'};
        }
    }

    # get all specified mysqld params from configs
    my $defined_vars = get_all_group_prms( $result, 'mysqld' );

    for my $hash (@compiled_to_analyse) {
        say "Processing " . $hash->{source} . " command output" if $opts{'v'};
        my $source = $hash->{source};

        # trim 'exec:' flag
        # $source =~ s/exec://;
        # $result->{$source} = { mysqld => {} };
        for my $prm (@$defined_vars) {

# make same structure as Config::MySQL::Reader->read_file and push to result hash
            $result->{$source}{mysqld}{$prm} =
              get_compiled_param( $hash->{content}, $prm );
        }
    }

    return $result;
}

# compare two values considering that _ and - symbols are same
# unit: ok

sub _match {
    my ( $x, $y ) = @_;
    return 1 if ( ( $y =~ s/-/_/rg ) eq ( $x =~ s/-/_/rg ) );
    return 0;
}

# accept array of strings
# unit: ok

sub get_compiled_param {
    my ( $strings, $param ) = @_;
    for my $str (@$strings) {

        # https://regex101.com/r/jQjDg5/1
        if ( $str =~ /^([a-z][a-z-]+)[\s\t]+(.*)\r/ ) {
            return $2 if _match( $param, $1 );
        }
    }
    return $NO_PARAM_MSG;
}

# Return value if all hash values are same and maped hash if no
# unit: ok

sub _try_group_hash {
    my %x      = @_;
    my @values = uniq values %x;
    return $values[0] if ( scalar @values == 1 );
    my $result;
    while ( my ( $key, $value ) = each(%x) ) {
        $result->{$key} = $value;
    }
    return $result;
}

# compare files readed by Config::MySQL::Reader
# unit: ok

sub compare {
    my ($h) = @_;

    my @filenames               = keys %$h;
    my @all_possible_ini_groups = uniq map { keys %$_ } values %$h;

    my $result;
    for my $group_name (@all_possible_ini_groups) {
        $result->{$group_name} =
          [ uniq map { keys %{ $h->{$_}{$group_name} } } @filenames ];
        my $temp = {};

        for my $param ( @{ $result->{$group_name} } ) {
            my %values = map { $_ => $h->{$_}{$group_name}{$param} } @filenames;
            $temp->{$param} = _try_group_hash(%values);
        }

        $result->{$group_name} = $temp;
    }

    return $result;
}

# if group_key->param_key->val = scalar push to 'same' key, otherwise to 'diff'
# unit: ok

sub split_compare_hash {
    my ($hash) = @_;

    my $res = {
        same => {},
        diff => {}
    };

    while ( my ( $group_name, $group_params ) = each(%$hash) ) {

        my ( $group_same, $group_diff ) = {};
        while ( my ( $param, $val ) = each(%$group_params) ) {

            if ( ref $val eq '' ) {
                $group_same->{$param} = $val;
            }
            else {
                $group_diff->{$param} = $val;
            }
        }

        $res->{same}{$group_name} = $group_same if (%$group_same);
        $res->{diff}{$group_name} = $group_diff if (%$group_diff);

    }
    return $res;
}

# unit: ok

sub find_keys_by_val {
    my ( $hash, $val ) = @_;
    my @res;
    while ( my ( $k, $v ) = each(%$hash) ) {
        push @res, $k if ( $v ~~ $val );
    }
    return [ sort @res ];
}

# must diff only once
# example of iteration two dimensional array

sub _can_same_path {
    my (@paths) = @_;

    my $keyword = '<some>';

    # validation - all @paths must be file/folder absolute paths
    for (@paths) {
        $_ =~ s/"//g;
        $_ =~ s/'//g;
    }
    return 0 if notall { file_name_is_absolute($_) } @paths;

    return $paths[0] if ( all { $paths[0] eq $_ } @paths );

    # path now is two dimensional array
    @paths = map {
        [ grep { $_ ne '' } splitdir($_) ]
    } @paths;

    # validation - all file paths must be same size
    return 0
      if notall { scalar @{ $paths[0] } == $_ } map { scalar @$_ } @paths;

    my $diff_counter = 0;
    my $path_size    = scalar @{ $paths[0] };
    my @common_path  = ('/');

    for my $i ( 1 .. $path_size ) {    # over size of path
        my @curr_vals = ();
        for my $j ( 0 .. $#paths ) {    # iterate over path
            push @curr_vals, $paths[$j][ $i - 1 ];
        }
        if ( notall { $curr_vals[0] eq $_ } @curr_vals ) {
            $diff_counter++;
            push @common_path, $keyword;
        }
        else {
            push @common_path, $curr_vals[0];
        }
    }

    return catfile(@common_path)
      if ( $diff_counter <= 1 );    # if only one diff in same position
    return 0;
}

# Prepare structure for writing using Config::MySQL::Writer
# key of $result will be source filename, value = hash with params

sub process_diff {
    my ( $hash, $defaults, $write_comment ) = @_;

    if ( $defaults && ( ref($defaults) ne 'HASH' ) ) {
        die "Wrong defaults specified";
    }

    my ( $res, $suggested_common ) = {};

    for my $grp ( keys %$hash ) {
        for my $prm ( sort keys %{ $hash->{$grp} } ) {

            my $no_zero = {};

            while ( my ( $source, $value ) = each( %{ $hash->{$grp}{$prm} } ) )
            {
                if ( !defined $defaults && $value ) {  # may leave value
                    $res->{$source}{$grp}{$prm} = $value;
                }

                $no_zero->{$source} = $value if ( $defaults && $value );
            }

            my @uniq = uniq values %$no_zero;
            
            # the main purpose of next block is to fill
            # $suggested_common->{$grp}{$param} 
            # and 
            # $res->{$_}{$grp}{$prm}

            if ($defaults) {
                
                if ( ( scalar @uniq == 1 ) && !defined $defaults->{$grp}{$prm} ) {
                    my $x = ( $write_comment ? $uniq[0]. ' # compiled default is not set' : $uniq[0] );
                    $suggested_common->{$grp}{$prm} = $x;
                }
                
                # write uniq as comment if compiled is same and exists
                # to indicate that if compiled defaults changed you will have to specify it manually
                elsif ( ( scalar @uniq == 1 ) && $defaults->{$grp}{$prm} && ( $defaults->{$grp}{$prm} ~~ $uniq[0] ) ) {
                    my $x = ( $write_comment ? '#' . $prm : $prm );
                    my $y = ( $write_comment ? $uniq[0] . ' # same as compiled' : $uniq[0] );
                    $suggested_common->{$grp}{$x} = $y;
                }
                
                elsif ( ( scalar @uniq == 1 ) && $defaults->{$grp}{$prm} && ( $defaults->{$grp}{$prm} !~ $uniq[0] ) ) {
                    my $x = ( $write_comment ? $uniq[0]. ' # compiled: '. $defaults->{$grp}{$prm} : $uniq[0] );
                    $suggested_common->{$grp}{$prm} = $x;
                }
                
                elsif ( scalar @uniq == 2 ) {
                    my %count = ();
                    foreach my $element ( values %$no_zero ) {
                        $count{$element}++;
                    }
                    my ( $max_by_count, $min_by_count ) = sort { $count{$b} <=> $count{$a} } keys %count;
                    
                    # $max_by_count to suggested defaults $min_by_count to corresponeded $source(s)
                    my $x = ( $write_comment ? $max_by_count . ' # ' . $min_by_count : $max_by_count );
                    $x.= ', compiled: ' . $defaults->{$grp}{$prm} if ( $defaults->{$grp}{$prm} && $write_comment );
                    $suggested_common->{$grp}{$prm} = $x;
                    my $s = find_keys_by_val( $no_zero, $min_by_count );    # defined sources to push
                    $res->{$_}{$grp}{$prm} = $min_by_count for (@$s);
                }
                
                elsif ( _can_same_path(@uniq) && !defined $defaults->{$grp}{$prm} ) {
                    my $x = ( $write_comment ? $uniq[0] . ' # ' . join( ', ', sort @uniq[1..$#uniq] ) : $uniq[0] );
                    $suggested_common->{$grp}{$prm} = $x;
                }
                
                elsif ( _can_same_path(@uniq) && $defaults->{$grp}{$prm} ) {
                    my $x = ( $write_comment ? $defaults->{$grp}{$prm} . ' # ' . join( ', ', sort @uniq ) : $defaults->{$grp}{$prm} );
                    $suggested_common->{$grp}{$prm} = $x;
                }
                
                else {
                    while ( my ( $k, $v ) = each(%$no_zero) ) {
                        $res->{$k}{$grp}{$prm} = $v;
                    }
                }
            } # end of if defaults
        } # end of for $prm
    } # end of for $grp

    return $res if !defined $defaults;
    return ( $res, $suggested_common );
}

1;
