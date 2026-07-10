import 'dart:convert';
import 'dart:math';
import 'package:sembast/sembast.dart';

SembastCodec getXorSembastCodec(String pin) {
  return SembastCodec(
    signature: 'xor_pin',
    codec: _XorCodec(pin),
  );
}

class _XorCodec extends Codec<Map<String, Object?>, String> {
  _XorCodec(this.pin);
  final String pin;

  @override
  Converter<Map<String, Object?>, String> get encoder => _XorEncoder(pin);

  @override
  Converter<String, Map<String, Object?>> get decoder => _XorDecoder(pin);
}

class _XorEncoder extends Converter<Map<String, Object?>, String> {
  _XorEncoder(this.pin);
  final String pin;

  @override
  String convert(Map<String, Object?> input) {
    final jsonStr = json.encode(input);
    final bytes = utf8.encode(jsonStr);
    final xored = _xor(bytes, pin);
    return base64.encode(xored);
  }
}

class _XorDecoder extends Converter<String, Map<String, Object?>> {
  _XorDecoder(this.pin);
  final String pin;

  @override
  Map<String, Object?> convert(String input) {
    final bytes = base64.decode(input);
    final xored = _xor(bytes, pin);
    final jsonStr = utf8.decode(xored);
    return json.decode(jsonStr) as Map<String, Object?>;
  }
}

List<int> _xor(List<int> bytes, String pin) {
  if (pin.isEmpty) return bytes;
  final seed = pin.codeUnits.fold<int>(0, (prev, element) => prev + element);
  final rand = Random(seed);
  return List<int>.generate(bytes.length, (i) => bytes[i] ^ rand.nextInt(256));
}
