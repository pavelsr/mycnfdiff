use Test::More;
use Config::MySQL::Reader;
use Data::Dumper;

# Test that Config::MySQL::Reader does not read comments

BEGIN {
    use_ok('Config::MySQL::Reader');
}

my $config = Config::MySQL::Reader->read_file('t/samples/patterns.ini');

my $res = {
    'group1' => {
        'string_param'                  => '500M',
        'param-with-two-spaces-after'   => undef,
        'path'                          => 'foo/bar',
        'param-without-value'           => undef,
        'param_with_comment'            => 'xyz',
        'param-with-tabulation-after  ' => undef,
        'empty_str ""'                  => undef,
        'quoted_param'                  => '"foo;bar"',
        'numerical_param'               => '12345'
    }
};

is_deeply $config, $res;

done_testing;
