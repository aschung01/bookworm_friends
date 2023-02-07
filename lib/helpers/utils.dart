import 'package:intl/intl.dart';

String formatPercentage(double val) {
  return '${getCleanTextFromDouble(val * 100)}%';
}

String formatNumberFromInt(int number) {
  var f = NumberFormat("###,###", "en_US");
  return f.format(number);
}

String formatNumberFromDouble(double number) {
  var f = NumberFormat("###,###.#", "en_US");
  return f.format(number);
}

String formatNumberFromStr(String number) {
  var f = NumberFormat("###,###", "en_US");
  return f.format(int.parse(number));
}

String getCleanTextFromDouble(num val) {
  if (val % 1 != 0) {
    return formatNumberFromDouble(val.toDouble());
  } else {
    return formatNumberFromInt(val.toInt());
  }
}

String formatDateTimeRawString(String rawString) {
  print(rawString);
  DateTime dt = DateTime.parse(rawString);
  print(dt);
  return DateFormat('yyyy. MM. dd. kk:mm').format(dt);
}

String formatDateRawString(String rawString) {
  print(rawString);
  DateTime dt = DateTime.parse(rawString);
  print(dt);
  return DateFormat('yyyy. MM. dd').format(dt);
}

String formatCurrentDDay(DateTime dueDate) {
  DateTime now = DateTime.now();

  Duration diff = dueDate.difference(now);
  if (diff.inDays < 1) {
    return "D-Day";
  } else {
    return "D-${diff.inDays}";
  }
}
