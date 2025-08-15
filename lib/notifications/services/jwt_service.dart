import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class JWTService {
  /// Create JWT token for Google OAuth using RS256
  static String createJWT({
    required String clientEmail,
    required String privateKey,
    required String scope,
    String audience = 'https://oauth2.googleapis.com/token',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    // JWT Header
    final header = {
      'alg': 'RS256',
      'typ': 'JWT',
    };
    
    // JWT Payload
    final payload = {
      'iss': clientEmail,
      'scope': scope,
      'aud': audience,
      'exp': now + 3600, // 1 hour
      'iat': now,
    };
    
    // Encode header and payload
    final encodedHeader = _base64UrlEncode(utf8.encode(json.encode(header)));
    final encodedPayload = _base64UrlEncode(utf8.encode(json.encode(payload)));
    
    // Create signature
    final message = '$encodedHeader.$encodedPayload';
    final signature = _signRS256(message, privateKey);
    final encodedSignature = _base64UrlEncode(signature);
    
    return '$message.$encodedSignature';
  }
  
  /// Sign message with RS256 using pointycastle
  static Uint8List _signRS256(String message, String privateKey) {
    try {
      // Parse the private key
      final rsaPrivateKey = _parsePrivateKey(privateKey);
      
      // Create signer
      final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
      signer.init(true, PrivateKeyParameter<RSAPrivateKey>(rsaPrivateKey));
      
      // Sign message
      final messageBytes = utf8.encode(message);
      final signature = signer.generateSignature(messageBytes);
      
      return signature.bytes;
    } catch (e) {
      throw Exception('Failed to sign JWT: $e');
    }
  }
  
  /// Parse RSA private key from PEM format
  static RSAPrivateKey _parsePrivateKey(String keyString) {
    try {
      // Remove PEM headers and whitespace
      final keyData = keyString
          .replaceAll('-----BEGIN PRIVATE KEY-----', '')
          .replaceAll('-----END PRIVATE KEY-----', '')
          .replaceAll('-----BEGIN RSA PRIVATE KEY-----', '')
          .replaceAll('-----END RSA PRIVATE KEY-----', '')
          .replaceAll(RegExp(r'\s+'), '');
      
      final keyBytes = base64.decode(keyData);
      
      // Parse the ASN.1 structure
      return _parseASN1PrivateKey(keyBytes);
    } catch (e) {
      throw Exception('Failed to parse private key: $e');
    }
  }
  
  /// Parse ASN.1 encoded private key
  static RSAPrivateKey _parseASN1PrivateKey(Uint8List keyData) {
    try {
      // This is a simplified ASN.1 parser for PKCS#8 format
      // For production use, consider using a proper ASN.1 library
      
      final parser = ASN1Parser(keyData);
      final topLevelSeq = parser.nextObject() as ASN1Sequence;
      
      // PKCS#8 format: SEQUENCE { version, algorithm, privateKey }
      if (topLevelSeq.elements!.length >= 3) {
        final privateKeyOctetString = topLevelSeq.elements![2] as ASN1OctetString;
        final privateKeyData = privateKeyOctetString.octets!;
        
        // Parse the inner RSA private key
        final innerParser = ASN1Parser(privateKeyData);
        final rsaSeq = innerParser.nextObject() as ASN1Sequence;
        
        if (rsaSeq.elements!.length >= 9) {
          // RSA private key components
          final modulus = (rsaSeq.elements![1] as ASN1Integer).integer!;
          final privateExponent = (rsaSeq.elements![3] as ASN1Integer).integer!;
          final p = (rsaSeq.elements![4] as ASN1Integer).integer!;
          final q = (rsaSeq.elements![5] as ASN1Integer).integer!;
          
          return RSAPrivateKey(modulus, privateExponent, p, q);
        }
      }
      
      throw Exception('Invalid private key format');
    } catch (e) {
      throw Exception('Failed to parse ASN.1 private key: $e');
    }
  }
  
  /// Base64 URL encode without padding
  static String _base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// Simple ASN.1 parser for basic operations
class ASN1Parser {
  final Uint8List _data;
  int _position = 0;
  
  ASN1Parser(this._data);
  
  ASN1Object nextObject() {
    if (_position >= _data.length) {
      throw Exception('End of data reached');
    }
    
    final tag = _data[_position++];
    final length = _readLength();
    final content = _data.sublist(_position, _position + length);
    _position += length;
    
    switch (tag) {
      case 0x30: // SEQUENCE
        return ASN1Sequence()..elements = _parseSequenceContent(content);
      case 0x02: // INTEGER
        return ASN1Integer()..integer = _parseInteger(content);
      case 0x04: // OCTET STRING
        return ASN1OctetString()..octets = content;
      default:
        return ASN1Object();
    }
  }
  
  int _readLength() {
    final firstByte = _data[_position++];
    
    if (firstByte & 0x80 == 0) {
      // Short form
      return firstByte;
    } else {
      // Long form
      final lengthBytes = firstByte & 0x7F;
      int length = 0;
      
      for (int i = 0; i < lengthBytes; i++) {
        length = (length << 8) | _data[_position++];
      }
      
      return length;
    }
  }
  
  List<ASN1Object> _parseSequenceContent(Uint8List content) {
    final objects = <ASN1Object>[];
    final parser = ASN1Parser(content);
    
    while (parser._position < content.length) {
      objects.add(parser.nextObject());
    }
    
    return objects;
  }
  
  BigInt _parseInteger(Uint8List content) {
    if (content.isEmpty) return BigInt.zero;
    
    // Handle negative numbers (two's complement)
    if (content[0] & 0x80 != 0) {
      // Negative number - not typically used in RSA keys
      throw Exception('Negative integers not supported');
    }
    
    // Convert bytes to BigInt
    BigInt result = BigInt.zero;
    for (final byte in content) {
      result = (result << 8) | BigInt.from(byte);
    }
    
    return result;
  }
}

/// Basic ASN.1 object classes
class ASN1Object {}

class ASN1Sequence extends ASN1Object {
  List<ASN1Object>? elements;
}

class ASN1Integer extends ASN1Object {
  BigInt? integer;
}

class ASN1OctetString extends ASN1Object {
  Uint8List? octets;
}
