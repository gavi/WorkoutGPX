# WorkoutGPX Development Guidelines

## Build Commands
- Build: `xcodebuild -project WorkoutGPX.xcodeproj -scheme WorkoutGPX build`
- Run: `xcodebuild -project WorkoutGPX.xcodeproj -scheme WorkoutGPX run`
- Test: `xcodebuild -project WorkoutGPX.xcodeproj -scheme WorkoutGPX test`
- Run single test: `xcodebuild -project WorkoutGPX.xcodeproj -scheme WorkoutGPX test -only-testing:WorkoutGPXTests/TestClassName/testMethodName`

## Code Style Guidelines
- **Imports**: Group imports by framework (SwiftUI, HealthKit, etc.) with a blank line between groups
- **Formatting**: 4-space indentation, line breaks after opening braces
- **Types**: Prefer Swift's strong type system with proper annotation when not inferrable
- **Naming**: Follow Apple's naming guidelines - descriptive, camelCase for variables/functions, PascalCase for types
- **Comments**: Use `//` for single-line comments, include descriptive comments before each struct/class
- **Error Handling**: Use do-catch blocks with specific error handling, use optional binding with guard statements
- **SwiftUI**: Group view modifiers logically, extract subviews to separate structs for complex views
- **HealthKit**: Handle permissions properly, check authorization status, use async/await for data queries
- **File Organization**: One main component per file, extensions in separate files when they grow large