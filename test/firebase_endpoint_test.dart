import 'package:flutter_test/flutter_test.dart';
import 'package:microart/features/recognition/firebase_endpoint.dart';

void main() {
  test('uses the origin of the current Cloudflare Quick Tunnel', () {
    final endpoint = parseCloudflareEndpoint(
      ' https://demo.trycloudflare.com/ ',
    );
    expect(endpoint.toString(), 'https://demo.trycloudflare.com');
  });

  test(
    'rejects missing configs and destinations outside the tunnel origin',
    () {
      for (final value in [
        null,
        {'url': 'https://demo.trycloudflare.com'},
        'http://demo.trycloudflare.com',
        'https://demo.trycloudflare.com.example.org',
        'https://user@demo.trycloudflare.com',
        'https://demo.trycloudflare.com/upload',
        'https://demo.trycloudflare.com:8443',
      ]) {
        expect(() => parseCloudflareEndpoint(value), throwsFormatException);
      }
    },
  );
}
