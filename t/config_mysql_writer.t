use Test::More;
use Config::MySQL::Writer;
use File::Slurper qw(read_text);
use Data::Dumper;

use_ok('Config::MySQL::Writer');

# Testing that Config::MySQL::Writer write in correct order if array specified
# In case of hash it writes in random order
# https://metacpan.org/pod/Config::INI::Writer#METHODS-FOR-WRITING-CONFIG
# https://metacpan.org/pod/Config::INI::Writer#preprocess_input

my $res = {
    'group1' => [
        '#p5' => 'abc # same as compiled',
        'p1' => 'abc # compiled: xyz',
        'p2' => 'x2 # x1, compiled: compiled_p2',
        'p4' => '"/somewhere/1.log" # "/foo/bar/1.log", "/foo/bat/1.log"',
    ]
};

my $result = <<END_MESSAGE;
[group1]
#p5 = abc # same as compiled
p1 = abc # compiled: xyz
p2 = x2 # x1, compiled: compiled_p2
p4 = "/somewhere/1.log" # "/foo/bar/1.log", "/foo/bat/1.log"
END_MESSAGE

my $filename = 'my.cnf';
Config::MySQL::Writer->write_file( $res, $filename );
my $content = read_text($filename);
unlink $filename;
is_deeply $content, $result, 'Config::MySQL::Writer wirtes in correct order if array specified';

done_testing;
