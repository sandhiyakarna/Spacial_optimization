# FlowSpace Frontend

The frontend for FlowSpace is built with **Flutter** (Material 3) utilizing **Riverpod** for state management and **GoRouter** for declarative navigation.

## Architecture

We use a **Feature-First** structure where features are organized by business domain:
* `app/`: Houses global routing (`router.dart`), visual styling (`themes/app_theme.dart`), and global app constants.
* `core/`: Houses long-lived infrastructure/service components like HTTP/API clients.
* `shared/`: Contains generic widgets (e.g. `responsive_layout.dart`), dialogs, icons, and layout frames that are shared across features.
* `features/`: The feature modules. Each feature folder contains:
  * `presentation/`: Widgets, pages, and ViewModels/state providers.
  * `domain/`: Business logic rules and entity models.
  * `data/`: Data sources and repository implementations.

## How to Run

1. Fetch Dart packages:
   ```bash
   flutter pub get
   ```

2. Run the application:
   ```bash
   flutter run
   ```

3. Run the widget and unit tests:
   ```bash
   flutter test
   ```
