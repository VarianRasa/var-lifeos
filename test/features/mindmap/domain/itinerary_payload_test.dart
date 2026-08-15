import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';

void main() {
  ItineraryPayload valid() => ItineraryPayload(
    destination: 'Kyoto',
    startDate: DateTime(2026, 10, 2),
    endDate: DateTime(2026, 10, 6),
    timezone: 'Asia/Tokyo',
    budget: 1000,
    actualCost: 250,
    travelers: 2,
    transport: 'Shinkansen',
    accommodation: 'Kyoto Station Hotel',
    bookingReference: 'JP-2026',
    bookings: [
      ItineraryBooking(
        id: 'hotel-booking',
        title: 'Kyoto hotel',
        type: 'hotel',
        startAt: DateTime(2026, 10, 2, 15),
        endAt: DateTime(2026, 10, 6, 11),
        provider: 'Example Stay',
        confirmationCode: 'HOTEL-1',
        cost: 400,
        status: 'confirmed',
      ),
    ],
    packing: const [
      ItineraryPackingItem(
        id: 'passport',
        title: 'Passport',
        category: 'documents',
        packed: true,
        essential: true,
      ),
    ],
    agenda: const [
      ItineraryAgendaItem(
        id: 'temple',
        title: 'Kiyomizu-dera',
        startMinutes: 540,
        durationMinutes: 120,
        dayOffset: 1,
        category: 'reservation',
        location: 'Higashiyama',
        cost: 20,
      ),
    ],
  );

  test('round trips and preserves unrelated data', () {
    final decoded = ItineraryPayload.fromData(valid().toData({'keep': 7}));
    expect(decoded.agenda.single.id, 'temple');
    expect(decoded.agenda.single.dayOffset, 1);
    expect(decoded.agenda.single.category, 'reservation');
    expect(decoded.travelers, 2);
    expect(decoded.transport, 'Shinkansen');
    expect(decoded.accommodation, 'Kyoto Station Hotel');
    expect(decoded.bookingReference, 'JP-2026');
    expect(decoded.bookings.single.confirmationCode, 'HOTEL-1');
    expect(decoded.packing.single.title, 'Passport');
    expect(decoded.agenda, isA<List<ItineraryAgendaItem>>());
    expect(valid().toData({'keep': 7})['keep'], 7);
    expect(
      () => decoded.agenda.add(decoded.agenda.single),
      throwsUnsupportedError,
    );
    expect(
      () => decoded.bookings.add(decoded.bookings.single),
      throwsUnsupportedError,
    );
    expect(
      () => decoded.packing.add(decoded.packing.single),
      throwsUnsupportedError,
    );
  });

  test('new node defaults dates to node day instead of 1970', () {
    final day = DateTime(2026, 7, 20);
    final node = MindmapNode.create(
      id: 'new-trip',
      type: NodeType.itinerary,
      title: 'New itinerary',
      day: day,
      now: day,
    );

    final payload = ItineraryPayload.fromNode(node);

    expect(payload.startDate, day);
    expect(payload.endDate, day);
    expect(payload.timezone, 'Local time');
    expect(payload.budget, 0);
    expect(payload.actualCost, 0);
  });

  test('validates dates costs identifiers and minute bounds', () {
    final payload = ItineraryPayload(
      destination: '',
      startDate: DateTime(2026, 10, 3),
      endDate: DateTime(2026, 10, 2),
      timezone: '',
      budget: -1,
      actualCost: -2,
      agenda: const [
        ItineraryAgendaItem(
          id: 'same',
          title: '',
          startMinutes: -1,
          durationMinutes: 0,
          cost: -1,
        ),
        ItineraryAgendaItem(
          id: 'same',
          title: 'Late',
          startMinutes: 1400,
          durationMinutes: 60,
        ),
      ],
    );
    final errors = payload.validate(title: '');
    expect(errors, contains('Title is required.'));
    expect(errors, isNot(contains('Destination is required.')));
    expect(errors, contains('End date must not precede start date.'));
    expect(errors, contains('Agenda IDs must be unique.'));
    expect(errors, contains('Agenda start minute must be within the day.'));
    expect(
      errors.where((error) => error == 'Agenda duration is invalid.'),
      hasLength(2),
    );
  });

  test('validates travelers status agenda day and category', () {
    final payload = valid().copyWith(
      travelers: 0,
      status: 'unknown',
      agenda: const [
        ItineraryAgendaItem(
          id: 'outside-trip',
          title: 'Unknown stop',
          startMinutes: 600,
          durationMinutes: 60,
          dayOffset: 99,
          category: 'unknown',
        ),
      ],
    );

    final errors = payload.validate(title: 'Trip');

    expect(errors, contains('Travelers must be between 1 and 100.'));
    expect(errors, contains('Itinerary status is invalid.'));
    expect(errors, contains('Agenda day must be inside the trip date range.'));
    expect(errors, contains('Agenda category is invalid.'));
  });

  test('validates booking and packing integrity', () {
    final payload = valid().copyWith(
      bookings: [
        ItineraryBooking(
          id: 'same',
          title: '',
          type: 'spaceship',
          startAt: DateTime(2026, 10, 4),
          endAt: DateTime(2026, 10, 3),
          cost: -1,
          status: 'unknown',
        ),
        ItineraryBooking(
          id: 'same',
          title: 'Duplicate',
          type: 'hotel',
          startAt: DateTime(2026, 10, 3),
          endAt: DateTime(2026, 10, 4),
        ),
      ],
      packing: const [
        ItineraryPackingItem(
          id: 'same',
          title: '',
          category: 'unknown',
          quantity: 0,
        ),
        ItineraryPackingItem(id: 'same', title: 'Duplicate'),
      ],
    );

    final errors = payload.validate(title: 'Trip');

    expect(errors, contains('Booking IDs must be unique.'));
    expect(errors, contains('Booking title is required.'));
    expect(errors, contains('Booking type is invalid.'));
    expect(errors, contains('Booking status is invalid.'));
    expect(errors, contains('Booking end must not precede start.'));
    expect(errors, contains('Packing item IDs must be unique.'));
    expect(errors, contains('Packing item title is required.'));
    expect(errors, contains('Packing quantity must be between 1 and 99.'));
    expect(errors, contains('Packing category is invalid.'));
  });

  test('calculates conflicts budget warnings and readiness', () {
    final payload = valid().copyWith(
      budget: 50,
      actualCost: 20,
      agenda: const [
        ItineraryAgendaItem(
          id: 'first',
          title: 'First',
          startMinutes: 540,
          durationMinutes: 120,
          cost: 10,
        ),
        ItineraryAgendaItem(
          id: 'second',
          title: 'Second',
          startMinutes: 600,
          durationMinutes: 60,
          cost: 10,
        ),
      ],
      bookings: [
        ItineraryBooking(
          id: 'pending-flight',
          title: 'Flight',
          type: 'flight',
          startAt: DateTime(2026, 10, 1, 9),
          endAt: DateTime(2026, 10, 1, 12),
          cost: 100,
          status: 'reserved',
        ),
      ],
      packing: const [
        ItineraryPackingItem(
          id: 'passport',
          title: 'Passport',
          category: 'documents',
          essential: true,
        ),
      ],
    );

    final insights = ItineraryInsights.fromPayload(payload);

    expect(insights.agendaConflicts, hasLength(1));
    expect(insights.totalPlannedCost, 120);
    expect(insights.pendingBookings, 1);
    expect(insights.bookingsOutsideTrip, 1);
    expect(insights.pendingEssentialItems, 1);
    expect(insights.overBudget, isTrue);
    expect(insights.readinessScore, 30);
    expect(insights.warnings, hasLength(5));
  });
}
