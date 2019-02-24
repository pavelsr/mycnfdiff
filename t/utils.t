use Test::More;
use Test::MockFile;
use Data::Dumper;
use File::Slurper qw/read_lines/;

BEGIN {
    use_ok( 'App::mycnfdiff::Utils', qw(:all) );
}

# subtest "get_folder" => sub {
#     Test::MockFile->dir("/fake/path", [ 'Foo.pm', 'bar.pl', 'test.ini', 'my.cnf' ] );
#     get_folder( dir => "/fake/path" );
# };

subtest "_match" => sub {
    ok _match( 'foo_bar', 'foo-bar' );
    ok _match( 'foo-bar', 'foo_bar' );
    ok !_match( 'foo', 'bar' );
};

subtest "_try_group_hash" => sub {
    my %h = ( 'file1' => 'v1', 'file2' => 'v2' );
    is_deeply \%{ _try_group_hash(%h) }, \%h;
    %h = ( 'file1' => 'v1', 'file2' => 'v1' );
    is_deeply _try_group_hash(%h), 'v1';
};

my $hash_for_split;
subtest "compare" => sub {
    my $h = {
        'file1' => {
            'mysqld' => {
                'p1' => 'v1',
                'p2' => 'v2'
            }
        },
        'file2' => {
            'mysqld' => {
                'p1' => 'v1',
                'p2' => 'v3'
            }
        }
    };

    my $res = {
        'mysqld' => {
            'p1' => 'v1',
            'p2' => {
                'file2' => 'v3',
                'file1' => 'v2'
            }
        }
    };

    $hash_for_split = compare($h);
    is_deeply $hash_for_split, $res;
};

subtest "split_compare_hash" => sub {
    my $res = {
        'diff' => {
            'mysqld' => {
                'p2' => {
                    'file1' => 'v2',
                    'file2' => 'v3'
                }
            }
        },
        'same' => {
            'mysqld' => {
                'p1' => 'v1'
            }
        }
    };

    is_deeply split_compare_hash($hash_for_split), $res;
};

subtest "get_compiled_param" => sub {
    my $f = 't/samples/percona-compiled.txt';

    # check problematic values at https://regex101.com/r/jQjDg5/1/
    my @content = read_lines($f);
    is get_compiled_param( \@content, 'auto-generate-certs' ),   "TRUE";
    is get_compiled_param( \@content, 'auto_generate_certs' ),   "TRUE";
    is get_compiled_param( \@content, 'back-log' ),              "80";
    is get_compiled_param( \@content, 'back_log' ),              "80";
    is get_compiled_param( \@content, 'basedir' ),               "/usr/";
    is get_compiled_param( \@content, 'bind-address' ),          '*';
    is get_compiled_param( \@content, 'bind_address' ),          '*';
    is get_compiled_param( \@content, 'binlog-error-action' ),   'ABORT_SERVER';
    is get_compiled_param( \@content, 'binlog_error_action' ),   'ABORT_SERVER';
    is get_compiled_param( \@content, 'block-encryption-mode' ), 'aes-128-ecb';
    is get_compiled_param( \@content, 'character-sets-dir' ),
      '/usr/share/mysql/charsets/';
    is get_compiled_param( \@content, 'chroot' ), '(No default value)';
    is get_compiled_param( \@content, 'collation-server' ), 'latin1_swedish_ci';
    is get_compiled_param( \@content, 'csv-mode' ),         '';
    is get_compiled_param( \@content, 'datetime-format' ),  '%Y-%m-%d %H:%i:%s';
    is get_compiled_param( \@content, 'ft-boolean-syntax' ), '+ -><()~*:""&|';
    is get_compiled_param( \@content, 'master-info-file' ),  'master.info';
    is get_compiled_param( \@content, 'optimizer-trace-features' ),
'greedy_search=on,range_optimizer=on,dynamic_range=on,repeated_subselect=on';
    is get_compiled_param( \@content, 'optimizer-trace-offset' ), '-1';
    is get_compiled_param( \@content, 'tls-version' ), 'TLSv1,TLSv1.1,TLSv1.2';
};

subtest "get_all_group_prms" => sub {
    my $h = {
        'my.cnf'     => { 'mysqld' => { 'basedir'      => '/usr' } },
        'my.cnf.bak' => { 'mysqld' => { 'basedir'      => '/mysql' } },
        'x.ini'      => { 'mysqld' => { 'bind-address' => '*' } },
        'y.ini'      => { 'mysqld' => { 'foo'          => '' } },
    };
    my $result = [ 'basedir', 'bind-address', 'foo' ];
    is_deeply get_all_group_prms( $h, 'mysqld' ), $result;
};

subtest "find_keys_by_val" => sub {
    my $h = { 'k1' => 'v1', 'k2' => 'v2', 'k3' => 'v1' };
    is_deeply find_keys_by_val( $h, 'v1' ), [ 'k1', 'k3' ];
};

subtest "_can_same_path" => sub {
    ok !_can_same_path( '/foo/bar',       '2' );           # one arg is not path
    ok !_can_same_path( '/foo/bar/bat',   '/foo/bar' );    # diff size
    ok !_can_same_path( '"/foo/bar/bat"', '"/foo/bar"' );  # diff size
    ok !_can_same_path( 'y1',             'y2', 'y3' );    # not abs path

    ok _can_same_path( '/foo/bar', '/foo/bar', '/foo/bar' )
      ;    # absolutely same folders
    ok _can_same_path( '/media/foo/mysql', '/media/bar/mysql',
        '/media/baz/mysql' );    # folders
    ok _can_same_path( '/foo/bar/xyz.txt', '/foo/bar/abc.txt' );    # files
    ok _can_same_path( '"/foo/baz/1.log"', '"/foo/bat/1.log"',
        '"/foo/bar/1.log"' );    # with quotes
};

subtest "process_diff" => sub {

    my $diff_mysqld = {
        'group1' => {
            'prm1' => {
                'source1' => undef,
                'source2' => '128',
                'source3' => undef,
                'source4' => undef
            },
            'prm2' => {
                'source1' => '"/foo/bar"',
                'source2' => '"/foo/bar"',
                'source3' => '"/foo/baz"',
                'source4' => '"/foo/bat"'
            }
        }
    };

    my $expected_config = {
        'source3' => {
            'group1' => {
                'prm2' => '"/foo/baz"'
            }
        },
        'source2' => {
            'group1' => {
                'prm2' => '"/foo/bar"',
                'prm1' => '128'
            }
        },
        'source1' => {
            'group1' => {
                'prm2' => '"/foo/bar"'
            }
        },
        'source4' => {
            'group1' => {
                'prm2' => '"/foo/bat"'
            }
        }
    };

    is_deeply process_diff($diff_mysqld), $expected_config, "Data 1";

    my $diff2_processed_expected = {
        's1' => {
            'group1' => {
                'p4' => '"/foo/bar/1.log"',
                'p3' => 'y1',
                'p1' => 'abc',
                'p2' => 'x1',
                'p5' => 'abc'
            }
        },
        's2' => {
            'group1' => {
                'p4' => '"/foo/baz/1.log"',
                'p2' => 'x2',
                'p3' => 'y2',
                'p1' => 'abc'
            }
        },
        's3' => {
            'group1' => {
                'p4' => '"/foo/bat/1.log"',
                'p2' => 'x2',
                'p3' => 'y3'
            }
        }
    };

    my $diff_2 = {
        'group1' => {
            'p1' => { 's1' => 'abc', 's2' => 'abc', 's3' => undef },
            'p2' => { 's1' => 'x1',  's2' => 'x2',  's3' => 'x2' },
            'p3' => { 's1' => 'y1',  's2' => 'y2',  's3' => 'y3' },
            'p4' => {
                's1' => '"/foo/bar/1.log"',
                's2' => '"/foo/baz/1.log"',
                's3' => '"/foo/bat/1.log"'
            },
            'p5' => { 's1' => 'abc', 's2' => undef, 's3' => undef },
        }
    };

    is_deeply process_diff($diff_2), $diff2_processed_expected, "Data 2";

    my $defaults = {
        'group1' => {
            'p1' => 'xyz',
            'p2' => 'compiled_p2',          # will be defined
            'p3' => 'ignored',              # will be ignored
            'p4' => '"/somewhere/1.log"',
            'p5' => 'abc'
        }
    };

    my $nc_expected = {
        'group1' => {
            'p5' => 'abc',
            'p1' => 'abc',
            'p2' => 'x1',
            'p4' => '"/somewhere/1.log"'
        }
    };

    my ( $individual, $common ) = process_diff( $diff_2, $defaults );

    my $ind_exp = {
        's3' => {
            'group1' => {
                'p3' => 'y3'
            }
        },
        's1' => {
            'group1' => {
                'p3' => 'y1',
                'p2' => 'x1'
            }
        },
        's2' => {
            'group1' => {
                'p3' => 'y2'
            }
        }
    };

    my $common_exp = {
        'group1' => {
            'p4' => '"/somewhere/1.log"',
            'p5' => 'abc',
            'p2' => 'x2',
            'p1' => 'abc'
        }
    };

    is_deeply $individual, $ind_exp,    'Without comments - individual';
    is_deeply $common,     $common_exp, 'Without comments - common';

    my ( $individual2, $common2 ) = process_diff( $diff_2, $defaults, 1 );
    is_deeply $individual2, $ind_exp,
      'With comments - individual was not changed';

    my $common_exp = {
        'group1' => {
            '#p5' => 'abc # compiled: abc',
            'p1'  => 'abc',
            'p2'  => 'x2 # x1, compiled: compiled_p2',
            'p4' => '"/somewhere/1.log" # "/foo/baz/1.log","/foo/bat/1.log","/foo/bar/1.log"'
        }
    };
    
    is_deeply $common2, $common_exp;

};

done_testing();
