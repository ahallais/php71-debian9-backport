#!/bin/bash
# $1 = old|new ; runs PHP's own test suites with the installed php7.1 CLI
cd /$1 && apt-get install -y -qq --no-install-recommends $(for f in /old/*.deb; do p=$(dpkg-deb -f $f Package); ls ./${p}_7.1*_amd64.deb; done) >/dev/null 2>&1
cp -a /srcro /src && cd /src
export TEST_PHP_EXECUTABLE=/usr/bin/php7.1 NO_INTERACTION=1 REPORT_EXIT_STATUS=0
php7.1 run-tests.php -q -d session.save_path=/tmp Zend/tests ext/session/tests tests/basic tests/lang ext/standard/tests/general_functions > /out/phpt-$1.log 2>&1
grep -E '^Tests (passed|failed|skipped)|^Number of tests' /out/phpt-$1.log
grep '^FAIL' /out/phpt-$1.log | sed 's/ \[.*//' | sort > /out/fail-$1.txt
