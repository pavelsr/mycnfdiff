use Test::More;
use Data::Dumper;
use File::Slurper qw/read_lines/;

BEGIN {
    use_ok( 'App::mycnfdiff::Utils', qw(:all) );
}

subtest "_match" => sub {
    ok _match( 'foo_bar', 'foo-bar' );
    ok _match( 'foo-bar', 'foo_bar' );
    ok !_match( 'foo', 'bar' );
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

done_testing();
