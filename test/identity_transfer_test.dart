// Tests for the identity transfer-code parser (lib/identity_transfer.dart)
// and for the seed -> identity derivation the import flow relies on.
//
// The fixture seed is a THROWAWAY test vector (bytes 0..31), never a real
// identity. Its expected public key was computed independently with OpenSSL,
// so the derive-check verifies the Dart Ed25519 path against an outside
// implementation.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_core_ui/omni_core_ui.dart';

import 'package:kickback/identity_transfer.dart';

/// Builds a code exactly the way LPE's identityTransferCode does, so the
/// parser is tested against the wire format, not against itself.
String _codeFor(List<int> seed) {
  final check = sha256.convert(seed).toString().substring(0, 8);
  return 'omni-seed-v1.${base64Encode(seed)}.$check';
}

void main() {
  final testSeed = List<int>.generate(32, (i) => i);
  const testPubkeyHex =
      '03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8';

  group('seedFromIdentityTransferCode', () {
    test('accepts a well-formed code and returns the seed', () {
      expect(seedFromIdentityTransferCode(_codeFor(testSeed)), testSeed);
    });

    test('accepts a code with surrounding whitespace (paste slop)', () {
      expect(seedFromIdentityTransferCode('  ${_codeFor(testSeed)}\n'),
          testSeed);
    });

    test('rejects a damaged checksum', () {
      final good = _codeFor(testSeed);
      final bad =
          '${good.substring(0, good.length - 1)}${good.endsWith('0') ? '1' : '0'}';
      expect(seedFromIdentityTransferCode(bad), isNull);
    });

    test('rejects a seed swapped under another seed\'s checksum', () {
      final other = List<int>.generate(32, (i) => 255 - i);
      final check = sha256.convert(testSeed).toString().substring(0, 8);
      final code = 'omni-seed-v1.${base64Encode(other)}.$check';
      expect(seedFromIdentityTransferCode(code), isNull);
    });

    test('rejects malformed input', () {
      expect(seedFromIdentityTransferCode(''), isNull);
      expect(seedFromIdentityTransferCode('hello'), isNull);
      expect(seedFromIdentityTransferCode('omni-seed-v1'), isNull);
      expect(
          seedFromIdentityTransferCode(
              'omni-seed-v2.${base64Encode(testSeed)}.630dcd29'),
          isNull);
      expect(
          seedFromIdentityTransferCode('omni-seed-v1.not!!base64.630dcd29'),
          isNull);
    });

    test('rejects a non-32-byte seed even with its own valid checksum', () {
      final short = List<int>.generate(16, (i) => i);
      expect(seedFromIdentityTransferCode(_codeFor(short)), isNull);
    });
  });

  group('import derivation', () {
    test('the fixture seed derives the expected public key', () async {
      final seed = seedFromIdentityTransferCode(_codeFor(testSeed));
      expect(seed, isNotNull);
      final identity = await StargateIdentity.fromSeed(seed!);
      expect(identity.pubkeyHex, testPubkeyHex);
      expect(identity.shortId, '03a1…31b8');
    });
  });
}
