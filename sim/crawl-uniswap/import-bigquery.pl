use strict;

use Date::Parse;
use DBI;

my $dbh = DBI->connect("dbi:SQLite:dbname=results.db","","");

my $sth = $dbh->prepare("INSERT INTO Block (blockNumber, timestamp) VALUES (?,?)");

$dbh->{AutoCommit} = 0;

while(<STDIN>) {
    /^(\d+),(.*)/ || next;
    my $blockNumber = $1;
    my $ts = str2time($2);
    $sth->execute($blockNumber, $ts);
    if ($blockNumber % 10000 == 0) {
        print "$blockNumber\n";
    }
}

$dbh->commit;
