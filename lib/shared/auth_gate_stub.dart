/// Web: there is no device authentication to ask for, so the answer is yes.
Future<bool> authenticateUser({String reason = 'Unlock your notebook'}) async {
  return true;
}
