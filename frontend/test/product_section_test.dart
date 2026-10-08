import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/data/product_section.dart';

Product _product(int id, ProductSection? section) => Product(
  id: id,
  shopId: 1,
  name: 'Товар $id',
  category: 'tools',
  unit: 'шт',
  price: 1000,
  availability: ProductAvailability.inStock,
  isTemplate: section != null,
  nameEditable: section == null,
  section: section,
);

void main() {
  final products = [
    _product(1, ProductSection.mixesPaints),
    _product(2, ProductSection.tapesAbrasives),
    _product(3, null),
    _product(4, ProductSection.mixesPaints),
    _product(5, ProductSection.tapesAbrasives),
  ];

  test('«Все товары» follows the chip order, keeps catalogue order inside, own rows last', () {
    expect([for (final p in productsBySection(products)) p.id], [2, 5, 1, 4, 3]);
  });

  test('a chip keeps only its own section', () {
    expect(
      [for (final p in productsBySection(products, only: ProductSection.mixesPaints)) p.id],
      [1, 4],
    );
  });

  test('only the sections in use get a chip, in enum order', () {
    expect(sectionsOf(products), [ProductSection.tapesAbrasives, ProductSection.mixesPaints]);
  });

  test('specs and section come off the wire, an unknown section is ignored', () {
    Product parse(String section) => Product.fromJson({
      'id': 1,
      'shop_id': 1,
      'name': 'LED-панель встраиваемая',
      'specs': 'Квадратная · 24 Вт · 6500 К',
      'section': section,
      'category': 'electrical',
      'unit': 'шт',
      'price': null,
    });
    expect(parse('electrical_lighting').specs, 'Квадратная · 24 Вт · 6500 К');
    expect(parse('electrical_lighting').section, ProductSection.electricalLighting);
    expect(parse('something_new').section, isNull);
  });
}
