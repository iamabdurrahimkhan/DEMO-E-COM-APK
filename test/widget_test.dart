import 'package:flutter_test/flutter_test.dart';
import 'package:suto_fashion/main.dart';

void main() {
  test('store URL is https and flags the app', () {
    final uri = Uri.parse(kStoreUrl);
    expect(uri.scheme, 'https');
    expect(uri.queryParameters['app'], '1');
  });
}
