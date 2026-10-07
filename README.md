# golden-env

Byte-identical Flutter golden tests on your Mac and on CI.

> [!NOTE]
> This project is fully vibe-coded: designed and written with an AI coding agent, reviewed by a human. Treat it accordingly.

Golden tests break when the machine that renders them changes: macOS and Linux rasterize text differently, and so do different CPUs. The usual fix is a pixel tolerance, which also hides real regressions.

golden-env removes the difference instead. One `linux/amd64` image, pinned by digest, is the only thing that ever renders a golden:

- **On CI**, the GitHub Action runs it with Docker on an x86-64 runner.
- **On your Mac**, `golden-run` boots the same image in a throwaway micro VM through Apple's [Containerization](https://github.com/apple/containerization), with Rosetta translating it. No Docker, no Flutter on the host.

Same `flutter_tester`, same FreeType, same fonts, same Skia code path: the same PNG bytes, with zero tolerance.

## Requirements

| Where | What |
|---|---|
| Mac | Apple Silicon, macOS 26 or newer, Rosetta (`softwareupdate --install-rosetta --agree-to-license`) |
| CI | An x86-64 Linux runner with Docker, such as GitHub's `ubuntu-24.04` |
| Your project | A Flutter version that has an image (see [Images](#images)) |

## Set up your project

**1. Pin the image** in `golden-env.lock` at the repository root. The tag is for people, the digest is what pins it:

```ini
image=ghcr.io/albert221/golden-env:3.47.6@sha256:<digest>
```

Get the digest with `docker buildx imagetools inspect ghcr.io/albert221/golden-env:3.47.6`, or copy it from the image's package page.

**2. Tag your golden tests**, so they can run in the image while the rest of the suite stays native:

```dart
testWidgets('profile card', tags: ['golden'], (tester) async {
  await tester.pumpWidget(const ProfileCard());
  await expectLater(find.byType(ProfileCard), matchesGoldenFile('goldens/profile_card.png'));
});
```

and declare the tag in `dart_test.yaml`:

```yaml
tags:
  golden:
```

**3. Load your fonts** in `test/flutter_test_config.dart`. The test font manager ignores installed fonts for app families, so without this every `fontFamily` falls back to the box-glyph `FlutterTest` font:

```dart
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader('Inter');
  for (final file in ['Inter-Regular.ttf', 'Inter-SemiBold.ttf']) {
    final bytes = File('assets/fonts/$file').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
  await testMain();
}
```

**4. Regenerate every golden in the image once** (`golden-run --update-goldens`) and commit them. Goldens rendered anywhere else will not match.

## Use it locally

Install the latest `golden-run`:

```bash
curl -fL https://github.com/albert221/golden-env/releases/latest/download/golden-run -o golden-run
chmod +x golden-run
sudo mv golden-run /usr/local/bin/
```

The binary is ad-hoc signed, not notarized. Downloading it with `curl` is what lets it run: a browser download gets quarantined and macOS will refuse to open it. If that happens, clear the flag with `xattr -d com.apple.quarantine golden-run`.

To check that a binary was built by this repository's release workflow:

```bash
gh attestation verify /usr/local/bin/golden-run --repo albert221/golden-env
```

Or build it yourself with `make release`, which also signs it with the virtualization entitlement it needs.

Then, from anywhere inside your Flutter package:

| Command | Does |
|---|---|
| `golden-run` | `flutter test --tags golden` in the image |
| `golden-run --update-goldens` | Regenerates goldens |
| `golden-run test/widgets/card_test.dart --name hover` | Any `flutter test` arguments pass through |
| `golden-run --all-tests` | Runs every test, not only tagged ones |
| `golden-run --offline` | No network in the VM, once dependencies are resolved |
| `golden-run shell` | A shell in the image, in your package directory |
| `golden-run doctor` | Checks macOS, Rosetta and what is downloaded |
| `golden-run pull` | Downloads the kernel and VM init ahead of time |

The first run downloads about 800 MB: a Linux kernel bundle (290 MB, once) and the image (about 500 MB, once per Flutter version). It then unpacks the image, which takes a few minutes. After that a run starts in under a second.

`golden-run` shares the whole git repository with the VM, so path dependencies elsewhere in a monorepo resolve, and runs as your user, so goldens it writes are yours. Your package's `.dart_tool` is left alone: the container keeps its own copy, so your IDE never sees paths from inside the image.

## Use it on CI

### GitHub Actions

```yaml
jobs:
  goldens:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: albert221/golden-env@v1
```

The action reads `golden-env.lock`, caches pub packages, runs your tagged goldens and, when they fail, uploads the `failures/` images as an artifact named after the job, so matrix jobs don't collide.

| Input | Default | |
|---|---|---|
| `working-directory` | `.` | Flutter package to test, relative to the repository root |
| `image` | from `golden-env.lock` | Image reference |
| `tags` | `golden` | Tags to select; empty runs every test |
| `reporter` | `github` | `flutter test` reporter; `github` groups the output and annotates failures |
| `args` | | Extra `flutter test` arguments, e.g. a test path |
| `update-goldens` | `false` | Regenerate instead of comparing |
| `upload-failures` | `true` | Upload failure images when tests fail |
| `artifact-name` | unique per job | Name of the failure artifact, e.g. `golden-failures-${{ matrix.package }}` |

To regenerate goldens on CI, for example from a manually triggered workflow, set `update-goldens: true` and commit the result in a later step.

The runner must be x86-64. ARM runners would emulate the image and render differently, so the action refuses them.

### Other CI systems

Any x86-64 Linux machine with Docker runs the same image:

```bash
docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" \
  -v "$PWD:/work" -w /work \
  ghcr.io/albert221/golden-env:3.47.6@sha256:<digest> \
  flutter test --tags golden
```

Run from the repository root and add `-w /work/<package>` for a package in a subdirectory. Mount a directory at `/opt/pub-cache` to keep pub packages between runs.

## Images

Images are published as `ghcr.io/albert221/golden-env:<flutter version>` for every version in [`golden-env/versions`](golden-env/versions). Each one is Debian trixie pinned by digest, the Flutter SDK cloned at the release commit and verified against it, the Inter font and nothing else, font hinting off, UTC and `C.UTF-8`.

For another version, add a line to `golden-env/versions` with the version and its framework commit, then build it:

```bash
make -C golden-env image FLUTTER_VERSION=3.47.5          # into Docker
make -C golden-env oci FLUTTER_VERSION=3.47.5            # as an OCI layout
golden-run load .build/golden-env-3.47.5.oci             # into golden-run, no registry needed
```

Bumping Flutter means a new image digest in `golden-env.lock` and a commit that regenerates every golden.

## When the Mac and CI disagree

[`canary/`](canary) holds five goldens that exercise text, gradients, blur, clipping, strokes and image scaling. They are rendered on a Mac with `golden-run` and checked by CI on every push, so a mismatch shows up here before it shows up in your project.

If your goldens differ between the two, compare `golden-run doctor` with the action's CPU log group. The image fixes everything except the CPU's vector instructions: Rosetta exposes AVX2 but not AVX-512, so a CI machine with AVX-512 can take a different Skia code path.

## License

[MIT](LICENSE)
