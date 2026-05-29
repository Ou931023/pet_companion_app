import '../controllers/profile_controller.dart';

class ContactLookupService {
  ContactLookupService(this._profileController);

  final ProfileController _profileController;

  Future<String?> lookupPhoneNumber(String contactName) async {
    final match = _findMatch(contactName);
    final phone = match?['phone'] ?? '';
    return phone.isEmpty ? null : phone;
  }

  Future<String?> lookupEmail(String contactName) async {
    final match = _findMatch(contactName);
    final email = match?['email'] ?? '';
    return email.isEmpty ? null : email;
  }

  Map<String, String>? _findMatch(String contactName) {
    final contacts = _profileController.familyContacts;
    if (contacts.isEmpty) return null;
    final query = contactName.trim().toLowerCase();
    if (query.isNotEmpty) {
      for (final c in contacts) {
        final alias = (c['alias'] ?? '').toLowerCase();
        if (alias.isNotEmpty &&
            (alias == query || alias.contains(query) || query.contains(alias))) {
          return c;
        }
      }
    }
    return contacts.first;
  }
}
