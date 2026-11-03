import 'package:frontend/core/constants/api_config.dart';
import 'product_section.dart';

// one product in a shop's catalogue, as returned by /api/shops/{id}/products. most are not created
// by anyone: picking a category at shop creation copies a ready-made template in, and the owner's
// job afterwards is filling in prices.
class Product {
  const Product({
    required this.id,
    required this.shopId,
    required this.name,
    required this.category,
    required this.unit,
    required this.price,
    required this.availability,
    required this.isTemplate,
    required this.nameEditable,
    this.photoEditable = true,
    this.imageUrl,
    this.thumbUrl,
    this.ownImage = false,
    this.inBasket = false,
    this.specs = '',
    this.section,
  });

  final int id;
  final int shopId;
  final String name;

  /// the group this product belongs to inside the shop, e.g. "Крепёж" - not the *shop's* category
  final String category;

  /// unit of measurement: шт, м², мешок ...
  final String unit;

  /// null means the owner has not set a price yet, which is where every template product starts.
  /// deliberately not 0 - "not priced" and "free" are different facts, and the whole seeded-catalogue
  /// flow depends on telling them apart.
  final int? price;

  final ProductAvailability availability;

  /// true when this row came from the category template. template rows can be edited but not deleted,
  /// and they do not count against the 20-product own-products cap.
  final bool isTemplate;

  /// whether the owner may write this product's name. two flags rather than one because an обои *slot*
  /// answers the two differently: it is a template row whose name is nonetheless the owner's to write,
  /// since the slot names a *kind* of product. for every other row the two agree.
  final bool nameEditable;

  /// Whether the owner may put their own photograph on this row.
  ///
  /// **The rule is "an owner photographs what we have not photographed"**: their own products, and
  /// обои slots, which have no object to shoot. Every other catalogue photo is one file shared by
  /// every shop of the category, and the index says a seeded row is *the same product* across the road.
  ///
  /// **Decided by the server and sent, never worked out here.** Defaults to true, as an older backend
  /// meant.
  final bool photoEditable;

  /// The photo at full size (1000px), or null when there is none. **The one an edit screen loads, not
  /// the one a grid loads** - see [thumbUrl]. The backend sends a root-relative path while the API
  /// serves photos itself and an absolute one once they move hosts; [Product.fromJson] handles both.
  final String? imageUrl;

  /// The 400px copy, which every catalogue grid loads. Null exactly when [imageUrl] is.
  ///
  /// **A hundred tiles at 1000px is roughly 15 MB; at 400px it is roughly 2.5 MB.** The address is
  /// sent by the server, never built here - an apk that appended "_thumb" itself would carry that
  /// convention until its owner updated. Falls back to [imageUrl] when absent, which is why no
  /// existing photo can disappear.
  final String? thumbUrl;

  /// Whether [imageUrl] is this shop's own upload rather than the shared catalogue photo. **It is what
  /// decides whether the edit screen offers "Удалить фото"**: on an own upload the photo goes, on a
  /// seeded row the catalogue's shot comes back, and on a row still showing that shot it would do
  /// nothing at all.
  final bool ownImage;

  /// Whether this row counts towards the shop's price comparison. **The comparison asks for a price on
  /// every basket row, not every template row**: a product added to the catalogue later starts outside
  /// the basket, so leaving it unpriced costs the shop nothing.
  final bool inBasket;

  /// the line under the name on a card - «Квадратная · 24 Вт · 6500 К». each size is its own row,
  /// so this is where the size lives. empty for an owner's own product.
  final String specs;

  /// the chip this row sits under in its shop, or null - see [ProductSection]
  final ProductSection? section;

  bool get hasPrice => price != null;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      shopId: json['shop_id'] as int,
      name: json['name'] as String,
      category: json['category'] as String,
      unit: json['unit'] as String,
      // `as int?` and not `as int`: the backend sends json null for an unpriced product
      price: json['price'] as int?,
      availability: ProductAvailability.fromCode(
        json['availability'] as String?,
      ),
      isTemplate: json['is_template'] as bool? ?? false,
      // defaults to "not a template row's rule", i.e. editable, so a build talking to a backend from
      // before slots existed behaves exactly as it did then: `!is_template`
      nameEditable:
          json['name_editable'] as bool? ??
          !(json['is_template'] as bool? ?? false),
      // true on a backend from before the rule existed, which is what that backend did
      photoEditable: json['photo_editable'] as bool? ?? true,
      imageUrl: ApiConfig.absoluteImageUrl(json['image_url'] as String?),
      // an older backend sends no image_thumb_url; falling back to the full-size photo is what this app
      // did before thumbnails existed
      thumbUrl:
          ApiConfig.absoluteImageUrl(json['image_thumb_url'] as String?) ??
          ApiConfig.absoluteImageUrl(json['image_url'] as String?),
      // false on a backend from before uploads existed, which is right there: every photo it can send is
      // a catalogue one
      ownImage: json['own_image'] as bool? ?? false,
      // a backend from before membership existed totalled every template row, which is what this says
      inBasket:
          json['in_basket'] as bool? ?? (json['is_template'] as bool? ?? false),
      specs: json['specs'] as String? ?? '',
      section: ProductSection.tryFromCode(json['section'] as String? ?? ''),
    );
  }

  /// The server sends a root-relative path while the API serves photos itself; the widget needs a full
  /// url. The absolute branch is what arrives once IMAGE_BASE_URL points at its own host, and is why
  /// the app needed no change when it did.
  Map<String, dynamic> toRequestJson() => {
    'name': name,
    'category': category,
    'unit': unit,
    'price': price, // null travels as json null, which is what clears a price
    'availability': availability.code,
  };

  /// [clearPrice] exists because `price: null` in a copyWith call is indistinguishable from "don't
  /// change the price" - the standard dart wart with nullable optional parameters.
  Product copyWith({
    String? name,
    String? category,
    String? unit,
    int? price,
    bool clearPrice = false,
    ProductAvailability? availability,
  }) {
    return Product(
      id: id,
      shopId: shopId,
      name: name ?? this.name,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      price: clearPrice ? null : (price ?? this.price),
      availability: availability ?? this.availability,
      isTemplate: isTemplate,
      nameEditable: nameEditable,
      photoEditable: photoEditable,
      imageUrl: imageUrl,
      thumbUrl: thumbUrl,
      ownImage: ownImage,
      inBasket: inBasket,
      specs: specs,
      section: section,
    );
  }
}

// the codes match the database CHECK constraint (backend/db/migrations/000004) and are
// locale-neutral for the same reason shop categories are: the display text is chosen in the app.
enum ProductAvailability {
  inStock('in_stock'),
  onOrder('on_order'),
  unavailable('unavailable');

  const ProductAvailability(this.code);

  final String code;

  /// unknown or missing falls back to [inStock] - the value the backend itself defaults to for a
  /// freshly seeded product
  static ProductAvailability fromCode(String? code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return ProductAvailability.inStock;
  }
}

// the same contract as ShopMutationException: the backend writes english and this app renders only
// ru/uz, so a failed save carries a stable machine-readable `code` that the ui localizes.
class ProductMutationException implements Exception {
  const ProductMutationException({
    required this.code,
    required this.message,
    this.limit,
  });

  final String code;
  final String message;

  /// only set for `product_limit_reached`, so the message can name the actual cap instead of
  /// hardcoding 20 in two places
  final int? limit;

  @override
  String toString() => 'ProductMutationException($code): $message';
}
