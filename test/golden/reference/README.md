# Golden reference shots

Drop the Day-0 SwiftUI reference screenshots here (PARITY_TRACKER "Reference
screenshots" section), then re-baseline the parity goldens against them.

Until those exist, parity goldens are **self-generated** (structure check):
the CI `flutter-parity.yml` workflow runs `flutter test --tags golden
--update-goldens` and uploads the generated PNGs under `test/golden/` as the
`parity-goldens` artifact for visual review. They are not a blocking gate yet.

Generated goldens live next to their tests (e.g. `test/golden/boards_living_wall.png`).
