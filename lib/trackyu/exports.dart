import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'api.dart';

String csvCell(dynamic value) {
  var text = value?.toString() ?? '';
  if (RegExp(r'^[\s]*[=+@-]').hasMatch(text)) text = "'$text";
  return '"${text.replaceAll('"', '""')}"';
}

String attendanceCsv(List<Json> rows) {
  const columns = [
    'userId',
    'workDate',
    'attendanceMode',
    'punchInUtc',
    'punchOutUtc',
    'isLate',
    'isEarly',
  ];
  return [
    columns.map(csvCell).join(','),
    ...rows.map((r) => columns.map((c) => csvCell(r[c])).join(',')),
  ].join('\r\n');
}

Future<String?> saveAttendanceExport(List<Json> rows) =>
    FilePicker.platform.saveFile(
      dialogTitle: 'Save loaded attendance records',
      fileName:
          'Trackyu-attendance-${DateTime.now().millisecondsSinceEpoch}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: Uint8List.fromList(utf8.encode('\uFEFF${attendanceCsv(rows)}')),
    );
