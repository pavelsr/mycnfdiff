package App::mycnfdiff::Utils;

use strict;
use warnings;
use feature 'say';
use Carp;

use List::Compare;
use List::Util qw(uniq);
use Config::MySQL::Reader;

use Data::Dump qw(dd);
use Data::Dumper;

use Const::Fast;
const my $ALLOWED_EXTENSIONS_REGEX => qr/\.ini|cnf$/;
const my $NO_PARAM_MSG => 'EMPTY';

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
  get_folder
  get_configs
  get_compiled_param
  compare
  split_compare_hash
  _match
);
our %EXPORT_TAGS = ( 'all' => [@EXPORT_OK] );

#Process skip files, filter extensions and return pwd-ed path

sub get_folder {
    my (%opts) = @_;

    say "Inspecting modules in " . $opts{'dir'} if $opts{'v'};
    say "Skip files : " . join( ',', @{ $opts{'skip'} } )
      if ( $opts{'v'} && @{ $opts{'skip'} } );

    my @files;
    opendir( my $dh, $opts{'dir'} ) or die $!;
    while ( my $file = readdir($dh) ) {
        # warn $file;
        next unless ( -f $opts{'dir'} . '/' . $file );
        next unless ( $file =~ m/$ALLOWED_EXTENSIONS_REGEX/ );
        push @files, $opts{'dir'}.'/'.$file;
    }
    closedir($dh);
    
    my $lc = List::Compare->new( \@files, $opts{'skip'} );
    return $lc->get_Lonly;
}

=head1 get_configs

Get content of configs into hash using L<Config::MySQL::Reader>

Resolve `exec:` tag in case of compiled defaults source using get_cd()

=cut

sub get_configs {
    my (%opts) = @_;

    my $result = {};
    my @compiled_to_analyse;

    if ( @{ $opts{'include_only'} } ) {
        
        for my $source ( @{ $opts{'include_only'} } ) {
            if ( $source =~ /exec:/ ) {  # detect_compiled_defaults_format
                my $cmd = (split( /:/, $source))[1];
                say "Executing external mysqld --verbose --help command : " . $cmd if $opts{'v'};
                my $content = `$cmd`;
                # split content by lines ?
                push { source => $source, content => $content }, @compiled_to_analyse;
            }
            else {
                $result->{$source} = Config::MySQL::Reader->read_file($source);
            }
        }
        
        # get all mysqld values
        my @defined_vars = get_all_mysql_prms($result);
        
        for my $hash (@compiled_to_analyse) {
            $result->{ $hash->{source} } = { mysqld => {} };
            for my $prm (@defined_vars) {
                # make same structure as Config::MySQL::Reader->read_file and push to result hash
                # this may not work    
                $result->{ $hash->{source} }{mysqld}{$prm} = get_compiled_param( $hash->{content}, $prm );
            }
        }
        
    }
    else {
        # read all files in specified directory considering --skip option
        my @files = get_folder(%opts);
        $result->{$_} = Config::MySQL::Reader->read_file($_) for (@files);
    }
    
    return $result;
}

# compare two values considering that _ and - symbols are same

sub _match {
    my ( $x, $y ) = @_;
    return 1 if ( ($y =~ s/-/_/rg) eq ($x =~ s/-/_/rg) );
    return 0;
}

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

sub _try_group_hash {
	my %x = @_;
	my @values = uniq values %x;
	return $values[0] if ( scalar @values == 1 );
	my $result;
	while (my ($key, $value) = each(%x)) {
  		$result->{$key} = $value;
	}	
	return $result;
}

# compare files readed by Config::MySQL::Reader

sub compare {
	my ( $h ) = @_;

	my @filenames = keys %$h;
	my @all_possible_ini_groups = uniq map { keys %$_ } values %$h;

	my $result;
	for my $group_name (@all_possible_ini_groups) {
		$result->{$group_name} = [ uniq map { keys %{ $h->{$_}{$group_name} } } @filenames ];
		my $temp = {};
        
		for my $param ( @{ $result->{$group_name} } ) {
			my %values = map { $_ => $h->{$_}{$group_name}{$param} } @filenames;
			$temp->{$param} = _try_group_hash(%values);
		}

		$result->{$group_name} = $temp;
	}

	return $result;
}

# if group_key->param_key->val = scalar push to same key, otherwise to diff

sub split_compare_hash {
	my ( $hash ) = @_;
	
    my $res = {
		same => {},
		diff => {}
	};

	while (my ($group_name, $group_params) = each(%$hash)) {

		my ( $group_same, $group_diff ) = {};
		while (my ($param, $val) = each(%$group_params)) {

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


1;
