/* Compact MD5 (RFC 1321) — hexMD5(str) interface used by RouterOS
   hotspot CHAP login pages. Public-domain style implementation. */
function hexMD5(input) {
  function rl(v, n) { return ((v << n) | (v >>> (32 - n))) | 0; }
  var s = unescape(encodeURIComponent(input));
  var M = [], i;
  for (i = 0; i < s.length; i++) {
    M[i >> 2] = (M[i >> 2] | 0) | (s.charCodeAt(i) << ((i & 3) * 8));
  }
  var byteLen = s.length;
  M[byteLen >> 2] = (M[byteLen >> 2] | 0) | (0x80 << ((byteLen & 3) * 8));
  var bitLen = byteLen * 8;
  M[(((bitLen + 64) >>> 9) << 4) + 14] = bitLen;
  var S = [7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
           5, 9,14,20,5, 9,14,20,5, 9,14,20,5, 9,14,20,
           4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
           6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21];
  var a0 = 1732584193, b0 = -271733879, c0 = -1732584194, d0 = 271733878;
  for (var c = 0; c < M.length; c += 16) {
    var a = a0, b = b0, cc = c0, d = d0;
    for (i = 0; i < 64; i++) {
      var f, g;
      if (i < 16)      { f = (b & cc) | (~b & d);  g = i; }
      else if (i < 32) { f = (d & b) | (~d & cc);  g = (5 * i + 1) % 16; }
      else if (i < 48) { f = b ^ cc ^ d;           g = (3 * i + 5) % 16; }
      else             { f = cc ^ (b | ~d);        g = (7 * i) % 16; }
      var K = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) | 0;
      var tmp = d; d = cc; cc = b;
      b = (b + rl((a + f + K + (M[c + g] | 0)) | 0, S[i])) | 0;
      a = tmp;
    }
    a0 = (a0 + a) | 0; b0 = (b0 + b) | 0;
    c0 = (c0 + cc) | 0; d0 = (d0 + d) | 0;
  }
  function le(n) {
    var h = '';
    for (var i = 0; i < 4; i++) {
      h += ('0' + ((n >> (i * 8)) & 255).toString(16)).slice(-2);
    }
    return h;
  }
  return le(a0) + le(b0) + le(c0) + le(d0);
}
