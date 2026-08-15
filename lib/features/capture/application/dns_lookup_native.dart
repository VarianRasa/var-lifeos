import 'dart:io';

Future<List<String>> platformLookupDns(String host) async {
  try {
    final addresses = await InternetAddress.lookup(host);
    return addresses.map((a) => a.address).toList();
  } catch (_) {
    return const [];
  }
}
