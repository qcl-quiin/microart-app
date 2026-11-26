import 'dart:convert';
import 'dart:io';

const _timeout = Duration(seconds: 6);

Future<Uri> readCloudflareEndpoint(String databaseUrl) async {
  final database = Uri.parse(databaseUrl);
  if (database.scheme != 'https' ||
      database.userInfo.isNotEmpty ||
      database.port != 443 ||
      !(database.host.endsWith('.firebaseio.com') ||
          database.host.endsWith('.firebasedatabase.app'))) {
    throw const FormatException('Expected a Firebase Realtime Database URL');
  }
  final configUrl = database.resolve('/microact/endpoint.json');
  final client = HttpClient()..connectionTimeout = _timeout;
  try {
    return await _readEndpoint(client, configUrl).timeout(_timeout);
  } finally {
    client.close(force: true);
  }
}

Future<Uri> _readEndpoint(HttpClient client, Uri configUrl) async {
  final request = await client.getUrl(configUrl);
  request.followRedirects = false;
  final response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    throw const HttpException('Firebase endpoint could not be read');
  }
  return parseCloudflareEndpoint(
    jsonDecode(await response.transform(utf8.decoder).join()),
  );
}

Uri parseCloudflareEndpoint(Object? value) {
  final url = value is String ? Uri.tryParse(value.trim()) : null;
  if (url == null ||
      url.scheme != 'https' ||
      !url.host.endsWith('.trycloudflare.com') ||
      url.port != 443 ||
      url.userInfo.isNotEmpty ||
      (url.path.isNotEmpty && url.path != '/') ||
      url.hasQuery ||
      url.hasFragment) {
    throw const FormatException('Expected a Cloudflare Quick Tunnel URL');
  }
  return Uri.parse(url.origin);
}
