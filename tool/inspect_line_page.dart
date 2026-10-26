// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:convert';
import 'dart:io';

import '../lib/core/line_following/line_layout.dart';

void main(List<String> args) {
  final result = LineLayout.prepare(File(args.single).readAsBytesSync());
  print(jsonEncode({'rows': result.rows.map((r) => r.toJson()).toList()}));
}
