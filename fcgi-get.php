<?php
// Minimal FastCGI client: php fcgi-get.php <unix-socket> <script-path> [POST body file]
function rec($type, $content, $id = 1) {
    $len = strlen($content);
    return pack('CCnnCx', 1, $type, $id, $len, 0) . $content;
}
function nv($k, $v) {
    $f = function ($l) { return $l < 128 ? chr($l) : pack('N', $l | 0x80000000); };
    return $f(strlen($k)) . $f(strlen($v)) . $k . $v;
}
list(, $sock, $script) = $argv;
$body = isset($argv[3]) ? file_get_contents($argv[3]) : '';
$params = [
    'SCRIPT_FILENAME' => $script, 'REQUEST_METHOD' => $body === '' ? 'GET' : 'POST',
    'CONTENT_LENGTH' => (string)strlen($body), 'SERVER_PROTOCOL' => 'HTTP/1.1',
    'CONTENT_TYPE' => isset($argv[4]) ? $argv[4] : 'application/x-www-form-urlencoded',
];
$p = '';
foreach ($params as $k => $v) $p .= nv($k, $v);
$s = stream_socket_client("unix://$sock", $en, $es, 5) or die("connect: $es\n");
fwrite($s, rec(1, pack('nCx5', 1, 0)) . rec(4, $p) . rec(4, ''));
foreach (str_split($body, 65535) as $chunk) if ($chunk !== '') fwrite($s, rec(5, $chunk));
fwrite($s, rec(5, ''));
$out = '';
while (($h = fread($s, 8)) !== false && strlen($h) == 8) {
    $r = unpack('Cver/Ctype/nid/nlen/Cpad', $h);
    $c = $r['len'] ? stream_get_contents($s, $r['len']) : '';
    if ($r['pad']) fread($s, $r['pad']);
    if ($r['type'] == 6) $out .= $c;
    if ($r['type'] == 3) break;
}
$parts = explode("\r\n\r\n", $out, 2);
echo isset($parts[1]) ? $parts[1] : $out, "\n";
