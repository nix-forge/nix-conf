add_executable(nix-conf-crashpad-lock-test nix-conf-crashpad-lock.cc)
target_link_libraries(nix-conf-crashpad-lock-test PRIVATE crashpad_client
                                                          crashpad_interface)
target_compile_options(
  nix-conf-crashpad-lock-test
  PRIVATE -Wall
          -Wextra
          -Wpedantic
          -Werror
          # Crashpad's abstract interface has intentionally unused default
          # parameters. Keep that vendor warning visible without making it
          # fatal.
          -Wno-error=unused-parameter)
