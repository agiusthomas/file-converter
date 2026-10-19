# Contributing

File Converter is in early development. Issues, fixes, accessibility improvements and new conversion engines are welcome.

## Development

Use a Mac with Xcode 26+ and the macOS 26 SDK. Apple silicon is the currently tested platform. The app's deployment target remains macOS 13; newer glass APIs have availability checks and material fallbacks.

```sh
git clone https://github.com/agiusthomas/file-converter.git
cd file-converter
./scripts/swift-local.sh test
./scripts/build-app.sh
open "build/File Converter.app"
```

The package currently has no third-party dependencies. The build scripts keep generated files and compiler caches within the project.

## Pull requests

- Describe the user-visible behavior and how you verified it.
- Preserve originals and validate outputs before publishing them.
- Add focused tests for conversion semantics, unsafe inputs or other meaningful failure cases that your change affects.
- Keep advertised format support consistent with actual engine capabilities.
- Use generated or permission-cleared fixtures. Do not include personal files, credentials, extracted proprietary source, or third-party application binaries/assets.
- For a new dependency, document its upstream source, pinned version and license.
- Run the tests and build the app. For gesture changes, also manually test Finder drags, cancellation, ordinary non-Shift drags and multiple displays where possible.

See [current status](IMPLEMENTATION.md) and [the roadmap](docs/ROADMAP.md) for scope and known limitations. Contributions are made under the project's [MIT license](LICENSE).
