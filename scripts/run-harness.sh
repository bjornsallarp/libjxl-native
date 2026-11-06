# Sourced by test.sh and smoke.sh (after versions.env and with $root set).
# run_harness <rid> <app-dir> <native-library|""> <dump-dir|"">
# Runs the harness on that RID: Linux in its .NET runtime image, macOS on this host.
# With a native library it tests that file; without one, .NET resolves jxl_native
# from the app's runtimes/<rid>/native/ (the package smoke test).
run_harness() {
  local rid=$1 app=$2 native=$3 dump=$4
  local args=()
  case $rid in
    linux-*)
      local image platform=linux/amd64
      case $rid in
        linux-x64) image=$DOTNET_RUNTIME_X64_IMAGE ;;
        linux-arm64) image=$DOTNET_RUNTIME_ARM64_IMAGE platform=linux/arm64 ;;
        linux-musl-x64) image=$DOTNET_RUNTIME_ALPINE_X64_IMAGE ;;
        linux-musl-arm64) image=$DOTNET_RUNTIME_ALPINE_ARM64_IMAGE platform=linux/arm64 ;;
        *) echo "unknown rid: $rid" >&2; return 1 ;;
      esac
      local docker=(docker run --rm --platform "$platform" -v "$app:/app:ro")
      if [[ -n $native ]]; then
        docker+=(-v "$(dirname "$native"):/native:ro" -e "JXL_NATIVE_PATH=/native/$(basename "$native")")
      fi
      if [[ -n $dump ]]; then mkdir -p "$dump"; docker+=(-v "$dump:/dump"); args+=(--dump /dump); fi
      "${docker[@]}" "$image" dotnet /app/Harness.dll ${args[@]+"${args[@]}"}
      ;;
    osx-arm64 | osx-x64)
      local dotnet=dotnet
      [[ $rid == osx-x64 ]] && dotnet=$(dotnet_x64)
      if [[ -n $dump ]]; then mkdir -p "$dump"; args+=(--dump "$dump"); fi
      JXL_NATIVE_PATH=$native "$dotnet" "$app/Harness.dll" ${args[@]+"${args[@]}"}
      ;;
    *) echo "unknown rid: $rid" >&2; return 1 ;;
  esac
}

# An x64 dotnet: the host's on an Intel Mac; on Apple silicon, a side-by-side x64
# install or an x64 runtime installed into build/ (runs under Rosetta).
dotnet_x64() {
  if [[ $(uname -m) == x86_64 ]]; then echo dotnet; return; fi
  local x64=/usr/local/share/dotnet/x64/dotnet
  if [[ ! -x $x64 ]]; then
    x64=$root/build/dotnet-x64/dotnet
    if [[ ! -x $x64 ]]; then
      curl -sSL https://dot.net/v1/dotnet-install.sh -o "$root/build/dotnet-install.sh"
      bash "$root/build/dotnet-install.sh" --runtime dotnet --channel 10.0 --architecture x64 \
        --install-dir "$root/build/dotnet-x64" --no-path >&2
    fi
  fi
  echo "$x64"
}
