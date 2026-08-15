import 'dns_lookup_stub.dart'
    if (dart.library.io) 'dns_lookup_native.dart'
    if (dart.library.js_interop) 'dns_lookup_web.dart';

typedef DnsResolver = Future<List<String>> Function(String host);

Future<List<String>> defaultDnsResolver(String host) => platformLookupDns(host);
