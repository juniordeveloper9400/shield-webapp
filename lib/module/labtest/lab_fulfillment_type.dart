/// How a member's lab sample reaches the lab — chosen once per basket on the
/// checkout screen (see `LabFulfillmentRow`), not per package.
enum LabFulfillmentType {
  /// The lab visits the member's own address (the original, default flow).
  homeCollection,

  /// The member visits the branch themselves — no delivery address needed.
  storeVisit;

  String get label => switch (this) {
    LabFulfillmentType.homeCollection => 'Home Collection',
    LabFulfillmentType.storeVisit => 'Store Visit',
  };

  /// The value `backend/api`'s `bookLabTestSchema` expects
  /// (`app.lab_booking_fulfillment`).
  String get apiValue => switch (this) {
    LabFulfillmentType.homeCollection => 'HOME_COLLECTION',
    LabFulfillmentType.storeVisit => 'STORE_VISIT',
  };
}
