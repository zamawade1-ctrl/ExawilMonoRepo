/// Mirrors the backend's `ForwardingMethod` enum (Models/Entities/Customer.cs) -
/// serialized as its numeric index, not a string.
enum ForwardingMethod {
  mobileNumber,
  bankAccount;

  static ForwardingMethod fromWire(int value) => ForwardingMethod.values[value];
}

/// The signed-in user's forwarding profile. For security the forwarding
/// destination and PINs are NEVER stored in the backend — they live only in the
/// device's on-device store — so this carries just the identity + chosen method.
class CustomerProfile {
  const CustomerProfile({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    required this.forwardingMethod,
    required this.isVerified,
  });

  factory CustomerProfile.fromJson(Map<String, dynamic> json) => CustomerProfile(
    id: json['id'] as int,
    fullName: json['fullName'] as String? ?? '',
    phoneNumber: json['phoneNumber'] as String? ?? '',
    forwardingMethod: ForwardingMethod.fromWire(json['forwardingMethod'] as int),
    isVerified: json['isVerified'] as bool? ?? false,
  );

  final int id;
  final String fullName;
  final String phoneNumber;
  final ForwardingMethod forwardingMethod;
  final bool isVerified;
}

/// What the form submits to PUT /api/customers/me. The destination + PINs are
/// intentionally NOT part of this payload — they're saved on-device only.
class ForwardingProfileInput {
  const ForwardingProfileInput({
    required this.fullName,
    this.phoneNumber,
    required this.forwardingMethod,
  });

  final String fullName;

  /// Optional: the on-device forwarder reads the account's own number from the
  /// *800# balance screen, so the form no longer collects it. Preserved on edit.
  final String? phoneNumber;
  final ForwardingMethod forwardingMethod;

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'phoneNumber': phoneNumber,
    'forwardingMethod': forwardingMethod.index,
  };
}
