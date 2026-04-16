import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _inr2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

String inr(num v, {bool decimals = false}) => decimals ? _inr2.format(v) : _inr.format(v);

String shortDate(DateTime d) => DateFormat('d MMM').format(d);
String fullDate(DateTime d) => DateFormat('d MMM yyyy').format(d);
String timeShort(DateTime d) => DateFormat('d MMM, h:mm a').format(d);
String monthLabel(DateTime d) => DateFormat('MMMM yyyy').format(d);
