import 'dart:io';

void main() {
  final lines = File('C:/Development/Oyu/TrackyuAPI/Controllers/RetailerMasterController.cs').readAsLinesSync();
  for (int i = 40; i < 80; i++) {
    print('${i + 1}: ${lines[i]}');
  }
}
