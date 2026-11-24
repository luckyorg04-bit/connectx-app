import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
Map<String, dynamic>? pendingCallArguments;

void openIncomingCall(Map<String, dynamic> arguments) {
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) {
    pendingCallArguments = arguments;
  } else {
    navigator.pushNamed(arguments['isGroupCall'] == true ? '/group-call' : '/call', arguments: arguments);
  }
}
