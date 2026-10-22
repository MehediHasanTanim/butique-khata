import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/customers/domain/save_customer.dart';
import 'package:tailor_khata/features/dev/seed_generator.dart';

import '../../support/test_app.dart';

void main() {
  late AppDatabase db;
  late DriftCustomerRepository repo;
  late FixedClock clock;
  late SaveCustomer save;
  late DeleteCustomer delete;

  setUp(() {
    db = memoryDb();
    repo = DriftCustomerRepository(db);
    clock = FixedClock(DateTime(2026, 3, 5, 10));
    save = SaveCustomer(repo, clock, SequentialIdGenerator('c'));
    delete = DeleteCustomer(repo, clock);
  });
  tearDown(() => db.close());

  Future<Customer> add(String name, [String phone = '']) async {
    final result = await save(CustomerInput(name: name, phone: phone));
    return result.valueOrNull!;
  }

  group('SaveCustomer', () {
    test('creates a customer with trimmed name and canonical phone', () async {
      final c = await add('  Rahim   Uddin ', '01712-345678');
      expect(c.name, 'Rahim Uddin');
      expect(c.phone, '+8801712345678');
      expect(c.phoneDisplay, '01712345678');
      expect((await repo.byId(c.id))?.name, 'Rahim Uddin');
    });

    test('name is required, invalid phone rejected, phone optional', () async {
      expect(
        (await save(const CustomerInput(name: '  '))).failureOrNull?.code,
        'customer.name_required',
      );
      expect(
        (await save(const CustomerInput(name: 'A', phone: '123')))
            .failureOrNull
            ?.code,
        'customer.phone_invalid',
      );
      expect((await save(const CustomerInput(name: 'Walk-in'))).isOk, isTrue);
    });

    test(
      'duplicate phone in any format is detected, can be overridden',
      () async {
        final first = await add('Rahim', '01712345678');
        final dup = await save(
          const CustomerInput(name: 'Karim', phone: '+88 01712-345678'),
        );
        final failure = dup.failureOrNull;
        expect(failure, isA<DuplicatePhoneFailure>());
        expect((failure! as DuplicatePhoneFailure).existing.id, first.id);

        final forced = await save(
          const CustomerInput(name: 'Karim', phone: '01712345678'),
          allowDuplicatePhone: true,
        );
        expect(forced.isOk, isTrue);
      },
    );

    test(
      'editing a customer keeps own phone without a duplicate error',
      () async {
        final c = await add('Rahim', '01712345678');
        final updated = await save(
          const CustomerInput(
            name: 'Rahim U',
            phone: '01712345678',
            note: 'VIP',
          ),
          existing: c,
        );
        expect(updated.valueOrNull?.name, 'Rahim U');
        expect(updated.valueOrNull?.note, 'VIP');
        expect((await repo.byId(c.id))?.note, 'VIP');
      },
    );

    test('update can clear the phone', () async {
      final c = await add('Rahim', '01712345678');
      await save(const CustomerInput(name: 'Rahim'), existing: c);
      expect((await repo.byId(c.id))?.phone, isNull);
    });
  });

  group('soft delete', () {
    test('hides from lists, search, duplicate checks; undo restores', () async {
      final c = await add('Rahim', '01712345678');
      await delete(c.id);
      expect(await repo.byId(c.id), isNull);
      expect(await repo.search('rah'), isEmpty);
      expect(await repo.findByPhone('+8801712345678'), isNull);
      expect(await repo.count(), 0);
      // The row still exists (history is never lost).
      expect(await db.select(db.customer).get(), hasLength(1));

      await delete.undo(c.id);
      expect((await repo.search('rah')).single.id, c.id);
      expect(await repo.count(), 1);
    });
  });

  group('search', () {
    setUp(() async {
      await add('Rahim Uddin', '01712345678');
      await add('Karim Hossain', '01898765432');
      await add('রহিম উদ্দিন', '01911112222');
      await add('ফাতেমা বেগম', '');
      await add('Fatema Begum', '01555000111');
    });

    Future<List<String>> names(String q) async =>
        (await repo.search(q)).map((c) => c.name).toList();

    test('prefix match on any name token, case-insensitive', () async {
      expect(await names('rah'), ['Rahim Uddin']);
      expect(await names('UDD'), ['Rahim Uddin']);
      expect(await names('rahim udd'), ['Rahim Uddin']);
      expect(await names('xyz'), isEmpty);
    });

    test('Bangla prefix search works through vowel signs', () async {
      expect(await names('রহ'), ['রহিম উদ্দিন']);
      expect(await names('রহিম'), ['রহিম উদ্দিন']);
      expect(await names('ফাতে'), ['ফাতেমা বেগম']);
      expect(await names('উদ্দি'), ['রহিম উদ্দিন']);
    });

    test('phone search is a substring of the national number', () async {
      expect(await names('01712'), ['Rahim Uddin']);
      expect(await names('345678'), ['Rahim Uddin']);
      expect(await names('+880 1898'), ['Karim Hossain']);
      expect(await names('০১৯১১'), ['রহিম উদ্দিন']);
    });

    test('empty query lists everyone sorted by name', () async {
      final all = await names('');
      expect(all, hasLength(5));
      expect(all.first, 'Fatema Begum');
    });

    test('quotes and operators in the query do not break FTS', () async {
      expect(await names('"'), isEmpty);
      expect(await names('rahim OR karim'), isEmpty);
      expect(await names('a*'), isA<List<String>>());
    });

    test('index follows edits', () async {
      final c = (await repo.search('karim')).single;
      await save(const CustomerInput(name: 'Salman Khan'), existing: c);
      expect(await names('karim'), isEmpty);
      expect(await names('salman'), ['Salman Khan']);
    });

    test('watchSearch re-emits when data changes', () async {
      final emissions = <int>[];
      final sub = repo
          .watchSearch('rah')
          .listen((l) => emissions.add(l.length));
      await pumpEventQueue();
      await add('Rahman Ali');
      await pumpEventQueue();
      await sub.cancel();
      expect(emissions, [1, 2]);
    });
  });

  test('search stays under 200 ms with 10,000 customers (S1-05)', () async {
    final seeds = SeedGenerator().customers(10000);
    final ids = SequentialIdGenerator('p');
    await db.transaction(() async {
      for (final s in seeds) {
        await repo.insert(
          Customer(
            id: ids.newId(),
            name: s.name,
            phone: '+88${s.phone}',
            createdAt: clock.now(),
            updatedAt: clock.now(),
          ),
        );
      }
    });
    expect(await repo.count(), 10000);

    for (final query in ['rah', 'রহ', '01712', '345', 'fat beg']) {
      final watch = Stopwatch()..start();
      final result = await repo.search(query);
      watch.stop();
      expect(
        watch.elapsedMilliseconds,
        lessThan(200),
        reason:
            '"$query" took ${watch.elapsedMilliseconds} ms '
            '(${result.length} rows)',
      );
    }
  });
}
