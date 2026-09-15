/// Where a delivering order ends up: shipped to the member's address, or held
/// at the store for them to collect.
///
/// Only meaningful for an order that ships at all — see
/// `CheckoutOrder.requiresDelivery` — a Health Pass activation has neither.
enum FulfillmentType {
  homeDelivery,
  storePickup;

  String get label => switch (this) {
    FulfillmentType.homeDelivery => 'Home Delivery',
    FulfillmentType.storePickup => 'Store Pickup',
  };
}
