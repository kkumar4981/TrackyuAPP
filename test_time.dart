void main() {
  final s1 = "11/20/2026 10:55:09 AM +05:30";
  final p1 = DateTime.tryParse(s1);
  print("p1: $p1");

  final s2 = "11/20/2026 10:55:09 AM";
  final p2 = DateTime.tryParse(s2);
  print("p2: $p2");

  final s3 = "2026-11-20T10:55:09";
  final p3 = DateTime.tryParse(s3);
  print("p3: $p3 (isUtc: ${p3?.isUtc}, toUtc: ${p3?.toUtc()})");

  final s4 = "2026-11-20 10:55:09";
  final p4 = DateTime.tryParse(s4);
  print("p4: $p4 (isUtc: ${p4?.isUtc}, toUtc: ${p4?.toUtc()})");
}
