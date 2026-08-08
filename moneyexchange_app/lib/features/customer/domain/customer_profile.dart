/// Mirrors the backend's `ForwardingMethod` enum (Models/Entities/Customer.cs) -
/// serialized as its numeric index, not a string.
enum ForwardingMethod {
  mobileNumber,
  bankAccount;

  static ForwardingMethod fromWire(int value) => ForwardingMethod.values[value];
}

/// The signed-in user's forwarding profile: where auto-forwarded USD should go.
class CustomerProfile {
  const CustomerProfile({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    required this.forwardingMethod,
    required this.isVerified,
    this.forwardingPhoneNumber,
    this.bankName,
    this.bankAccountNumber,
    this.bankAccountHolderName,
  });

  factory CustomerProfile.fromJson(Map<String, dynamic> json) => CustomerProfile(
    id: json['id'] as int,
    fullName: json['fullName'] as String? ?? '',
    phoneNumber: json['phoneNumber'] as String? ?? '',
    forwardingMethod: ForwardingMethod.fromWire(json['forwardingMethod'] as int),
    isVerified: json['isVerified'] as bool? ?? false,
    forwardingPhoneNumber: json['forwardingPhoneNumber'] as String?,
    bankName: json['bankName'] as String?,
    bankAccountNumber: json['bankAccountNumber'] as String?,
    bankAccountHolderName: json['bankAccountHolderName'] as String?,
  );

  final int id;
  final String fullName;
  final String phoneNumber;
  final ForwardingMethod forwardingMethod;
  final bool isVerified;
  final String? forwardingPhoneNumber;
  final String? bankName;
  final String? bankAccountNumber;
  final String? bankAccountHolderName;

  /// Bank forwarding is now a single PIN rather than name/number/holder. Stored
  /// in the backend's `bankAccountNumber` column (repurposed - avoids a schema
  /// migration for a still-unused rail). Unlike the on-device Keystore mobile
  /// PINs, this is returned by the backend, so it can be pre-filled on edit.
  String? get bankAccountPin => bankAccountNumber;
}

/// What the form submits to PUT /api/customers/me.
class ForwardingProfileInput {
  const ForwardingProfileInput({
    required this.fullName,
    this.phoneNumber,
    required this.forwardingMethod,
    this.forwardingPhoneNumber,
    this.bankName,
    this.bankAccountNumber,
    this.bankAccountHolderName,
  });

  final String fullName;

  /// Optional: the on-device forwarder reads the account's own number from the
  /// *800# balance screen, so the form no longer collects it. Preserved on edit.
  final String? phoneNumber;
  final ForwardingMethod forwardingMethod;
  final String? forwardingPhoneNumber;
  final String? bankName;
  final String? bankAccountNumber;
  final String? bankAccountHolderName;

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'phoneNumber': phoneNumber,
    'forwardingMethod': forwardingMethod.index,
    'forwardingPhoneNumber': forwardingPhoneNumber,
    'bankName': bankName,
    'bankAccountNumber': bankAccountNumber,
    'bankAccountHolderName': bankAccountHolderName,
  };
}
