import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';

// **Which of a product's two photos each surface loads.** a shop card is up to a hundred tiles, so a
// grid reaching for the full-size copy is ~15 MB down a mobile connection instead of ~2.5 MB - and it
// fails invisibly: every picture is correct, the screen is just six times slower.
//
// The server sends both addresses ready-made and **the app never builds one**.

Map<String, dynamic> _json({String? image, String? thumb}) => {
  'id': 7,
  'shop_id': 1,
  'name': 'Цемент М400',
  'category': 'mixes',
  'unit': 'мешок',
  'price': 52000,
  'availability': 'in_stock',
  'is_template': true,
  'name_editable': false,
  // null-aware entries: a null drops the key entirely, which is what an older backend sends
  'image_url': ?image,
  'image_thumb_url': ?thumb,
};

void main() {
  test('a product keeps both addresses the server sent', () {
    final product = Product.fromJson(
      _json(
        image: '/static/products/universal/001.jpg',
        thumb: '/static/products/universal/001_thumb.jpg',
      ),
    );

    expect(
      product.imageUrl,
      '${ApiConfig.serverRoot}/static/products/universal/001.jpg',
    );
    expect(
      product.thumbUrl,
      '${ApiConfig.serverRoot}/static/products/universal/001_thumb.jpg',
    );
  });

  // a backend from before thumbnails existed sends only image_url. the app has to keep drawing that
  // photo rather than the placeholder — no existing picture may disappear because the server is old.
  test('a response with no thumbnail falls back to the full-size photo', () {
    final product = Product.fromJson(
      _json(image: '/static/products/universal/001.jpg'),
    );

    expect(product.thumbUrl, product.imageUrl);
    expect(product.thumbUrl, isNotNull);
  });

  test('a product with no photo has neither address', () {
    final product = Product.fromJson(_json());

    expect(product.imageUrl, isNull);
    expect(product.thumbUrl, isNull);
  });

  // an absolute url is what arrives once IMAGE_BASE_URL points photos at their own host, and the
  // app must not prepend its own server root to it
  test('an absolute address is passed through untouched', () {
    final product = Product.fromJson(
      _json(
        image: 'https://photos.example/universal/001.jpg',
        thumb: 'https://photos.example/universal/001_thumb.jpg',
      ),
    );

    expect(product.thumbUrl, 'https://photos.example/universal/001_thumb.jpg');
  });

  testWidgets('the grid tile loads the thumbnail, not the full-size photo', (
    tester,
  ) async {
    final product = Product.fromJson(
      _json(
        image: 'https://photos.example/universal/001.jpg',
        thumb: 'https://photos.example/universal/001_thumb.jpg',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductTile(
            product: product,
            strings: AppLocalizations(AppLanguage.ru),
          ),
        ),
      ),
    );

    // the network image never resolves in a test harness, which is fine: what is under test is the
    // address the tile asked for, and that is decided at build time.
    //
    // unwrapping ResizeImage is not incidental — `cacheWidth` is what stops a 99-tile grid holding
    // 99 full-size bitmaps, so a provider that is *not* wrapped is its own bug
    final image = tester.widget<Image>(find.byType(Image));
    final resize = image.image as ResizeImage;
    expect((resize.imageProvider as NetworkImage).url, product.thumbUrl);
    expect((resize.imageProvider as NetworkImage).url, isNot(product.imageUrl));
  });
}
