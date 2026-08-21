import 'package:frontend/core/constants/api_config.dart';

// one product in a shop's catalogue, as returned by the go backend's /api/shops/{id}/products.
//
// most products are not created by anyone: picking a category when the shop is created copies a
// ready-made template into it (backend/internal/catalog), and the owner's job afterwards is filling
// in prices and adding the handful of products unique to their shop.
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
  });

  final int id;
  final int shopId;
  final String name;

  /// the group this product belongs to inside the shop, e.g. "Крепёж" - not the *shop's* category
  final String category;

  /// unit of measurement: шт, м², мешок ...
  final String unit;

  /// null means the owner has not set a price yet, which is the state every template product starts
  /// in. deliberately not 0 - "we haven't priced this" and "this is free" are different facts, and
  /// the whole seeded-catalogue flow depends on telling them apart to prompt for the missing ones.
  final int? price;

  final ProductAvailability availability;

  /// true when this row came from the category template rather than from the owner. template rows
  /// can be edited but not deleted, and they don't count against the 20-product own-products cap.
  final bool isTemplate;

  /// whether the owner may write this product's name. two flags rather than one, because an обои
  /// *slot* answers the two questions differently: it is a template row (locked category and unit,
  /// no delete button) whose name is nonetheless the owner's to write, since the slot describes a
  /// kind of product - "премиальные российские обои" - and the shop supplies the collection it
  /// actually stocks. for every other row the two flags agree.
  final bool nameEditable;

  /// Whether the owner may put their own photograph on this row.
  ///
  /// **The rule is "an owner photographs what we have not photographed".** Their own products
  /// always; обои slots, which name a *kind* of wallpaper and so have no object to shoot; and
  /// древесные материалы, which has never been shot. The универсальный and сантехника catalogues are
  /// ours - one file on disk shared by every shop of the category - and the basket index says a
  /// seeded row is *the same product* as its counterpart across the road, so one owner swapping the
  /// picture puts two different objects on two tiles of one product.
  ///
  /// **Decided by the server and sent, never worked out here**, for the reason [nameEditable] is:
  /// what it really asks is whether the template names a photo for this row, which is a fact only
  /// the backend holds - and an app that inferred it from the shop's category would go wrong the day
  /// the wood catalogue is photographed.
  ///
  /// Defaults to true, which is what a backend from before the rule existed meant: it accepted a
  /// photo on any row in the owner's shop.
  final bool photoEditable;

  /// The product's photo at full size (1000px), ready to hand to `Image.network`, or null when it
  /// has no photo. **This is the one an edit screen loads, not the one a grid loads** - see
  /// [thumbUrl].
  ///
  /// The backend sends a root-relative path ("/static/products/universal/001.jpg") while photos are
  /// served by the API itself, and an absolute one ("https://img.domix-api.uz/universal/001.jpg")
  /// once they move to their own host; [Product.fromJson] prepends [ApiConfig.serverRoot] to the
  /// first shape and leaves the second alone, so nothing downstream has to know which it got.
  final String? imageUrl;

  /// The 400px copy of the same photo, which is what every catalogue grid loads. Null exactly when
  /// [imageUrl] is.
  ///
  /// **A hundred tiles at 1000px is roughly 15 MB; at 400px it is roughly 2.5 MB**, and a shop card
  /// is a hundred tiles on a phone tethered to mobile data. That is what this field is for.
  ///
  /// **The address is sent by the server, never built here.** The backend derives it from the
  /// master's path by a naming rule, and the rule is deliberately not in this file: an apk that
  /// appended "_thumb" itself would carry that convention until its owner updated, so changing the
  /// convention would mean a release in Play rather than a deploy - and the builds that guessed
  /// wrong could not be fixed at all.
  ///
  /// Falls back to [imageUrl] when the field is absent, which is what a backend from before
  /// thumbnails existed sends. That fallback is the reason no existing photo can disappear.
  final String? thumbUrl;

  /// Whether [imageUrl] is this shop's own upload rather than the shared catalogue photo the row was
  /// seeded with.
  ///
  /// **It is what decides whether the edit screen offers "Удалить фото".** Removing means two
  /// different things: on the owner's own upload the photo goes, and on a seeded row the catalogue's
  /// shot comes back. On a row that is *still showing* the catalogue's shot it would do nothing at
  /// all - so without this flag the button would be dead on most of a fresh shop's catalogue, which
  /// is the kind of control people press twice and then report as broken.
  final bool ownImage;

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
      availability: ProductAvailability.fromCode(json['availability'] as String?),
      isTemplate: json['is_template'] as bool? ?? false,
      // defaults to "not a template row's rule", i.e. editable, so a build talking to a backend
      // from before slots existed behaves exactly as it did then: `!is_template`
      nameEditable: json['name_editable'] as bool? ?? !(json['is_template'] as bool? ?? false),
      // true on a backend from before the rule existed, which is what that backend did
      photoEditable: json['photo_editable'] as bool? ?? true,
      imageUrl: _absoluteImageUrl(json['image_url'] as String?),
      // an older backend sends no image_thumb_url at all; falling back to the full-size photo is
      // exactly what this app did before thumbnails existed
      thumbUrl: _absoluteImageUrl(
            json['image_thumb_url'] as String?,
          ) ??
          _absoluteImageUrl(json['image_url'] as String?),
      // false on a backend from before uploads existed, which is exactly right there: every photo it
      // could send is a catalogue one
      ownImage: json['own_image'] as bool? ?? false,
    );
  }

  /// The server sends "/static/products/universal/001.jpg" while the API serves photos itself; the
  /// widget needs a full url. The absolute branch is not hypothetical any more - it is what arrives
  /// once IMAGE_BASE_URL points at img.domix-api.uz, and it is why the app needed no change when it
  /// did.
  static String? _absoluteImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${ApiConfig.serverRoot}$path';
  }

  Map<String, dynamic> toRequestJson() => {
        'name': name,
        'category': category,
        'unit': unit,
        'price': price, // null travels as json null, which is what clears a price
        'availability': availability.code,
      };

  /// [clearPrice] exists because `price: null` in a copyWith call is indistinguishable from "don't
  /// change the price" - the standard dart wart with nullable optional parameters. only the edit
  /// form needs it, and only to blank a price the owner deleted.
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
    );
  }
}

// stock status. the codes match the database CHECK constraint (backend/db/migrations/000004) and
// are locale-neutral for the same reason shop categories are: the display text is chosen in the app.
enum ProductAvailability {
  inStock('in_stock'),
  onOrder('on_order'),
  unavailable('unavailable');

  const ProductAvailability(this.code);

  final String code;

  /// unknown or missing falls back to [inStock] - the value the backend itself defaults to for a
  /// freshly seeded product (see SeedTemplateProduct in db/queries/products.sql)
  static ProductAvailability fromCode(String? code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return ProductAvailability.inStock;
  }
}

// same contract as ShopMutationException: the backend's messages are
// english and this app renders only ru/uz, so a failed save carries a stable machine-readable
// `code` (see writeAPIError in backend/internal/endpoints/authz.go) that the ui localizes.
class ProductMutationException implements Exception {
  const ProductMutationException({required this.code, required this.message, this.limit});

  final String code;
  final String message;

  /// only set for `product_limit_reached`, so the message can name the actual cap instead of
  /// hardcoding 20 in two places
  final int? limit;

  @override
  String toString() => 'ProductMutationException($code): $message';
}
