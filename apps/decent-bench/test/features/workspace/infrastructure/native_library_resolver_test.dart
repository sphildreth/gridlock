import 'package:decent_bench/features/workspace/infrastructure/native_library_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers DECENTDB_NATIVE_LIB when it exists', () async {
    final resolver = NativeLibraryResolver(
      environment: const <String, String>{
        'DECENTDB_NATIVE_LIB': '/custom/libc_api.so',
      },
      currentDirectoryPath: '/workspace/apps/decent-bench',
      scriptDirectoryPath: '/workspace/apps/decent-bench/tool',
      resolvedExecutablePath: '/workspace/apps/decent-bench/decent_bench',
      platform: NativeLibraryPlatform.linux,
      fileExists: (path) => path == '/custom/libc_api.so',
    );

    expect(await resolver.resolve(), '/custom/libc_api.so');
  });

  test(
    'runtime resolution checks bundled library locations before repo search',
    () async {
      final resolver = NativeLibraryResolver(
        environment: const <String, String>{},
        currentDirectoryPath: '/workspace/apps/decent-bench',
        scriptDirectoryPath: '/workspace/apps/decent-bench/tool',
        resolvedExecutablePath: '/bundle/decent_bench',
        platform: NativeLibraryPlatform.linux,
        fileExists: (path) => path == '/bundle/lib/libc_api.so',
      );

      final result = await resolver.resolveDetailed();

      expect(result.resolvedPath, '/bundle/lib/libc_api.so');
      expect(result.checkedPaths.first, '/bundle/lib/libc_api.so');
    },
  );

  test(
    'packaging resolution skips bundled paths and finds sibling decentdb build',
    () async {
      final resolver = NativeLibraryResolver(
        environment: const <String, String>{},
        currentDirectoryPath: '/workspace/apps/decent-bench',
        scriptDirectoryPath: '/workspace/apps/decent-bench/tool',
        resolvedExecutablePath: '/bundle/decent_bench',
        platform: NativeLibraryPlatform.linux,
        fileExists: (path) => path == '/workspace/decentdb/build/libc_api.so',
      );

      final result = await resolver.resolveDetailed(
        mode: NativeLibraryResolutionMode.packagingSource,
      );

      expect(result.resolvedPath, '/workspace/decentdb/build/libc_api.so');
      expect(
        result.checkedPaths.any((path) => path == '/bundle/lib/libc_api.so'),
        isFalse,
      );
    },
  );

  test('bundle relative install path matches platform conventions', () {
    final linux = NativeLibraryResolver(
      environment: const <String, String>{},
      currentDirectoryPath: '/tmp',
      scriptDirectoryPath: '/tmp',
      resolvedExecutablePath: '/tmp/decent_bench',
      platform: NativeLibraryPlatform.linux,
      fileExists: (_) => false,
    );
    final macos = NativeLibraryResolver(
      environment: const <String, String>{},
      currentDirectoryPath: '/tmp',
      scriptDirectoryPath: '/tmp',
      resolvedExecutablePath: '/tmp/decent_bench',
      platform: NativeLibraryPlatform.macos,
      fileExists: (_) => false,
    );
    final windows = NativeLibraryResolver(
      environment: const <String, String>{},
      currentDirectoryPath: r'C:\tmp',
      scriptDirectoryPath: r'C:\tmp',
      resolvedExecutablePath: r'C:\tmp\decent_bench.exe',
      platform: NativeLibraryPlatform.windows,
      fileExists: (_) => false,
    );

    expect(linux.bundleRelativeInstallPath, 'lib/libc_api.so');
    expect(
      macos.bundleRelativeInstallPath,
      'Contents/Frameworks/libc_api.dylib',
    );
    expect(windows.bundleRelativeInstallPath, 'c_api.dll');
  });

  test(
    'failure includes the invalid env path and checked candidates',
    () async {
      final resolver = NativeLibraryResolver(
        environment: const <String, String>{
          'DECENTDB_NATIVE_LIB': '/missing/libc_api.so',
        },
        currentDirectoryPath: '/workspace/apps/decent-bench',
        scriptDirectoryPath: '/workspace/apps/decent-bench/tool',
        resolvedExecutablePath: '/bundle/decent_bench',
        platform: NativeLibraryPlatform.linux,
        fileExists: (_) => false,
      );

      await expectLater(
        resolver.resolve(),
        throwsA(
          isA<NativeLibraryResolutionFailure>()
              .having(
                (error) => error.requestedEnvPath,
                'requestedEnvPath',
                '/missing/libc_api.so',
              )
              .having(
                (error) => error.toString(),
                'message',
                allOf(
                  contains('/missing/libc_api.so'),
                  contains('/bundle/lib/libc_api.so'),
                  contains('Set DECENTDB_NATIVE_LIB'),
                ),
              ),
        ),
      );
    },
  );
}
