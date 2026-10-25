import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowspace_frontend/features/room/presentation/room_list_screen.dart';
import 'package:flowspace_frontend/features/room/providers/room_provider.dart';
import 'package:flowspace_frontend/features/room/presentation/panorama_capture_step.dart';

class MockRoomListNotifier extends RoomListNotifier {
  @override
  RoomListState build() {
    return const RoomListState(
      isLoading: false,
      rooms: [
        {
          'id': 'room-123',
          'project_id': 'project-123',
          'room_name': 'Test Salon',
          'room_type': 'Living Room',
          'floor_number': 1,
          'notes': 'Elegant living room',
          'room_color': '#FFFFFF',
        }
      ],
    );
  }

  @override
  Future<void> fetchRooms(String projectId) async {
    // No-op to preserve mock state in testing
  }
}

class MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return MockHttpClient();
  }
}

class MockHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getUrl || invocation.memberName == #get) {
      return Future.value(MockHttpClientRequest());
    }
    return null;
  }
}

class MockHttpClientRequest implements HttpClientRequest {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #close) {
      return Future.value(MockHttpClientResponse());
    }
    if (invocation.memberName == #headers) {
      return MockHttpHeaders();
    }
    return null;
  }
}

class MockHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockHttpClientResponse implements HttpClientResponse {
  static const List<int> _transparentImageBytes = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #statusCode) return 200;
    if (invocation.memberName == #contentLength) return _transparentImageBytes.length;
    if (invocation.memberName == #headers) return MockHttpHeaders();
    if (invocation.memberName == #reasonPhrase) return "OK";
    if (invocation.memberName == #compressionState) return HttpClientResponseCompressionState.notCompressed;
    if (invocation.memberName == #listen) {
      final handler = invocation.positionalArguments[0] as void Function(List<int>);
      final onDone = invocation.namedArguments[#onDone] as void Function()?;
      final onError = invocation.namedArguments[#onError] as Function?;
      final cancelOnError = invocation.namedArguments[#cancelOnError] as bool?;
      return Stream<List<int>>.fromIterable([_transparentImageBytes]).listen(
        handler,
        onDone: onDone,
        onError: onError,
        cancelOnError: cancelOnError,
      );
    }
    return null;
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = MockHttpOverrides();
  });

  testWidgets('Verify RoomListScreen renders rooms list and triggers add dialog', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomListProvider.overrideWith(() => MockRoomListNotifier()),
        ],
        child: const MaterialApp(
          home: RoomListScreen(projectId: 'project-123'),
        ),
      ),
    );

    await tester.pump();

    // Verify page title and custom mock room name are rendered
    expect(find.text('Rooms Catalog'), findsOneWidget);
    expect(find.text('Test Salon'), findsOneWidget);
    expect(find.text('Type: Living Room • Floor: 1'), findsOneWidget);

    // Verify Add Room button is shown
    expect(find.text('Add Room'), findsWidgets);

    // Tap Add Room button to show dialog
    await tester.tap(find.text('Add Room').last);
    await tester.pumpAndSettle();

    // Verify Add Room dialog popped up
    expect(find.text('Room Creation Wizard'), findsOneWidget);
  });

  testWidgets('Verify SpatialRoomCaptureStep builds and transitions to capturing mode without layout assertions', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpatialRoomCaptureStep(
            onPanoramaSelected: (url) {},
            onSkip: () {},
            onBack: () {},
          ),
        ),
      ),
    );

    await tester.pump();

    // Verify "Spatial Room Capture" option is rendered
    expect(find.text('Spatial Room Capture'), findsOneWidget);

    // Tap "Spatial Room Capture" to transition to capturing mode
    await tester.tap(find.text('Spatial Room Capture'));
    await tester.pumpAndSettle();

    // Verify it transitions to SpatialRoomCaptureScreen's instructions view
    expect(find.text('Interactive 360° Spatial Scanner'), findsOneWidget);
  });
}
