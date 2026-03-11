import 'dart:typed_data';

import 'package:decent_bench/features/import/infrastructure/type_inference_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = TypeInferenceService();

  test('infers common DecentDB target types', () {
    expect(service.inferTargetType(<Object?>['1', '2', '3']), 'INTEGER');
    expect(service.inferTargetType(<Object?>['true', 'false']), 'BOOLEAN');
    expect(service.inferTargetType(<Object?>['2026-03-11T04:00:00Z']), 'TIMESTAMP');
    expect(
      service.inferTargetType(<Object?>['d290f1ee-6c54-4b01-90e6-d701748f0851']),
      'UUID',
    );
    expect(service.inferTargetType(<Object?>[Uint8List(2)]), 'BLOB');
  });

  test('keeps leading-zero identifiers as text', () {
    expect(service.inferTargetType(<Object?>['0012', '0013']), 'TEXT');
  });

  test('sanitizes and deduplicates identifiers', () {
    expect(
      service.distinctTargetNames(
        <String>['Order ID', 'Order ID', '2nd value'],
        fallbackPrefix: 'column',
      ),
      <String>['Order_ID', 'Order_ID_2', 'column_2nd_value'],
    );
  });
}
