import 'package:civicconnect_ai/core/di/app_dependencies.dart';
import 'package:civicconnect_ai/core/models/app_role.dart';
import 'package:civicconnect_ai/core/services/location_service.dart';
import 'package:civicconnect_ai/core/services/reverse_geocoder.dart';
import 'package:civicconnect_ai/core/theme/app_theme.dart';
import 'package:civicconnect_ai/core/utils/geo.dart';
import 'package:civicconnect_ai/core/widgets/civic_widgets.dart';
import 'package:civicconnect_ai/features/citizen/presentation/cubit/create_complaint_cubit.dart';
import 'package:civicconnect_ai/features/complaints/domain/complaint.dart';
import 'package:civicconnect_ai/features/complaints/domain/services/complaint_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'harness.dart';

const fix = GeoPoint(27.5296, 68.7626);

Future<CreateComplaintCubit> formCubit({
  required LocationResult location,
  String? geocoded,
  FakeReverseGeocoder? geocoder,
}) async {
  SharedPreferences.setMockInitialValues({});
  final deps = AppDependencies(await SharedPreferences.getInstance(),
      locationService: FakeLocationService(result: location),
      mediaPicker: FakeMediaPicker());
  return CreateComplaintCubit(
    service: deps.complaintService,
    location: FakeLocationService(result: location),
    media: FakeMediaPicker(),
    actor: Actor.demoCitizen,
    wardCentre: const GeoPoint(24.86, 67.0),
    geocoder: geocoder ?? FakeReverseGeocoder(address: geocoded),
  );
}

void main() {
  group('GPS → readable address', () {
    test('a successful lookup fills the empty address field', () async {
      final cubit = await formCubit(
          location: const LocationResult.success(fix),
          geocoded: 'Station Road, Civil Lines, Khairpur');
      await cubit.detectLocation();
      expect(cubit.state.location, fix, reason: 'GPS capture is unchanged');
      expect(cubit.state.locationSource, LocationSource.gps);
      expect(cubit.state.address, 'Station Road, Civil Lines, Khairpur');
      expect(cubit.state.addressAutoFilled, isTrue);
      expect(cubit.state.addressFillId, 1);
      expect(ComplaintValidator.address(cubit.state.address), isNull);
      expect(cubit.state.locationMessage, contains('Address filled in'));
    });

    test('a typed address is never overwritten', () async {
      final geocoder = FakeReverseGeocoder(address: 'Station Road');
      final cubit = await formCubit(
          location: const LocationResult.success(fix), geocoder: geocoder);
      cubit.updateText(address: 'Opposite the pharmacy');
      await cubit.detectLocation();
      expect(cubit.state.address, 'Opposite the pharmacy');
      expect(cubit.state.addressFillId, 0);
      expect(cubit.state.location, fix);
      expect(cubit.state.locationMessage, contains('Your address was kept'));
    });

    test('tapping again replaces only an auto-filled address', () async {
      final geocoder = FakeReverseGeocoder(address: 'Station Road');
      final cubit = await formCubit(
          location: const LocationResult.success(fix), geocoder: geocoder);
      await cubit.detectLocation();
      geocoder.address = 'Bus Stand Road';
      await cubit.detectLocation();
      expect(cubit.state.address, 'Bus Stand Road');
      expect(cubit.state.addressFillId, 2);

      // Editing the suggestion makes it the user's own address.
      cubit.updateText(address: 'Bus Stand Road, gate 2');
      expect(cubit.state.addressAutoFilled, isFalse);
      geocoder.address = 'Somewhere else';
      await cubit.detectLocation();
      expect(cubit.state.address, 'Bus Stand Road, gate 2');
    });

    test('failed lookup keeps coordinates and does not block submission',
        () async {
      final cubit = await formCubit(
          location: const LocationResult.success(fix), geocoded: null);
      await cubit.detectLocation();
      expect(cubit.state.location, fix);
      expect(cubit.state.address, 'GPS 27.52960, 68.76260');
      expect(ComplaintValidator.address(cubit.state.address), isNull,
          reason: 'valid coordinates must not fail address validation');
      expect(cubit.state.locationMessage, contains('could not be found'));
    });

    test('permission denied: no lookup, manual entry still possible', () async {
      final geocoder = FakeReverseGeocoder(address: 'unused');
      final cubit = await formCubit(
          location: const LocationResult.failed(LocationFailure.denied),
          geocoder: geocoder);
      await cubit.detectLocation();
      expect(cubit.state.location, isNull);
      expect(cubit.state.address, isEmpty);
      expect(geocoder.lookups, 0);
      expect(cubit.state.locationMessage, contains('permission denied'));
    });

    test('GPS unavailable: falls back to manual pin message', () async {
      final geocoder = FakeReverseGeocoder(address: 'unused');
      final cubit = await formCubit(
          location: const LocationResult.failed(LocationFailure.error),
          geocoder: geocoder);
      await cubit.detectLocation();
      expect(cubit.state.location, isNull);
      expect(geocoder.lookups, 0);
      expect(cubit.state.locationMessage, contains('unavailable'));
    });

    testWidgets('Use my location fills the address field on the form',
        (tester) async {
      await bootApp(tester,
          prefs: rolePrefs('citizen'),
          size: const Size(1400, 1000),
          location:
              FakeLocationService(result: const LocationResult.success(fix)),
          geocoder: FakeReverseGeocoder(address: 'Station Road, Khairpur'));
      await tester.tap(find.text('Report issue'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Use my location'));
      final field =
          tester.widget<TextField>(find.byKey(const Key('addressField')));
      expect(field.controller!.text, 'Station Road, Khairpur');
      expect(tester.takeException(), isNull);
    });
  });

  group('NominatimReverseGeocoder (free OSM lookup)', () {
    Map<String, dynamic> sample() => {
          'display_name':
              'Station Road, Civil Lines, Khairpur, Sindh, Pakistan',
          'address': {
            'road': 'Station Road',
            'suburb': 'Civil Lines',
            'city': 'Khairpur',
            'state': 'Sindh',
          },
        };

    test('formats road, area and city', () {
      expect(NominatimReverseGeocoder.formatAddress(sample()),
          'Station Road, Civil Lines, Khairpur');
      expect(
          NominatimReverseGeocoder.formatAddress(
              {'display_name': 'A, B, C, D'}),
          'A, B, C');
      expect(NominatimReverseGeocoder.formatAddress({}), isNull);
    });

    test('identifies the app, caches results, and fails quietly', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.url.host, 'nominatim.openstreetmap.org');
        expect(request.headers['User-Agent'], contains('CivicConnectAI'));
        return http.Response.bytes(
            '{"address":{"road":"Station Road","city":"Khairpur"}}'.codeUnits,
            200);
      });
      final geocoder = NominatimReverseGeocoder(client: client);
      expect(await geocoder.addressFor(fix), 'Station Road, Khairpur');
      expect(await geocoder.addressFor(const GeoPoint(27.52961, 68.76261)),
          'Station Road, Khairpur');
      expect(requests, 1, reason: 'same ~11 m cell is served from cache');

      final failing = NominatimReverseGeocoder(
          client: MockClient((_) async => http.Response('busy', 429)));
      expect(await failing.addressFor(fix), isNull);
      final offline = NominatimReverseGeocoder(
          client: MockClient((_) async => throw Exception('offline')));
      expect(await offline.addressFor(fix), isNull);
    });
  });

  group('header refinement', () {
    testWidgets('CivicAppBar keeps title, subtitle, actions and height',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          appBar: CivicAppBar(
              title: 'Complaint queue',
              subtitle: 'Municipal Admin',
              actions: [
                IconButton(
                    tooltip: 'Notifications',
                    onPressed: () {},
                    icon: const Icon(Icons.notifications_outlined)),
              ]),
        ),
      ));
      expect(find.text('Complaint queue'), findsOneWidget);
      expect(find.text('Municipal Admin'), findsOneWidget);
      expect(find.byTooltip('Notifications'), findsOneWidget);
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.toolbarHeight, 68, reason: 'height unchanged');
      expect(bar.bottom, isNull, reason: 'no extra height below the bar');
      expect(bar.backgroundColor, AppTheme.lightTheme.colorScheme.surface);
      expect(bar.shape, isA<Border>());
    });
  });
}
