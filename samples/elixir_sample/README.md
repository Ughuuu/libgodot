# LibGodotConnector (Elixir)

This is a proof-of-concept showing how to interface Elixir with LibGodot using NIFs.

## Architecture

1.  **Elixir to Godot:** The `LibGodot` module provides functions like `start/0` and `iteration/0` which call into the C++ NIF.
	It also provides `send_message/2`, which enqueues messages for Godot to consume via the `ElixirBus` singleton.
2.  **Godot to Elixir:** Godot can call `ElixirBus.send_event(kind, payload)` to push events back to the subscribed Elixir process.
	You can "subscribe" a process using `LibGodot.subscribe(self())`.

## How to build

1.  Ensure you have built `libgodot` in the root directory.
2.  Build the NIF via Mix (recommended):

```bash
cd samples/elixir_sample
mix deps.get
mix compile
```

This uses `elixir_make` and the local `Makefile` to drive a CMake build.

### Optional: use precompiled NIFs from GitHub Releases

If you publish precompiled artefacts (tarballs) to GitHub Releases for the current version,
`mix compile` can download them instead of building locally.

```bash
cd samples/elixir_sample
mix compile
```

To override the default URL template, set `LIBGODOT_PRECOMPILED_URL` to a template containing
`@{artefact_filename}`.

To force a local build (skip download attempts):

```bash
export LIBGODOT_FORCE_BUILD=1
mix compile
```

## Using this as a dependency (local + Hex)

This project is set up to work like a typical Hex package that ships **precompiled** NIFs.

Key idea: end-users installing from Hex should not need C++ tooling. During `mix compile`, `elixir_make` will:

1. Determine the current target triple (see `LibGodotConnector.Precompiler.current_target/0`).
2. Compute the expected artefact filename (`@{artefact_filename}` in the URL template).
3. Download and unpack the tarball into the dependency's `priv/` directory.
4. Optionally verify checksums using `checksum-lib_godot_connector.exs` if it is present in the Hex package.

If the precompiled artefact is missing/unavailable, `elixir_make` falls back to building locally (unless `LIBGODOT_FORCE_BUILD=1` is set).

### Test "install elsewhere" locally (without publishing)

1. Create a new scratch Elixir project somewhere else:

```bash
mix new /tmp/test_libgodot_dep
cd /tmp/test_libgodot_dep
```

2. Add a path dependency to this sample in `/tmp/test_libgodot_dep/mix.exs`:

```elixir
defp deps do
	[
		{:lib_godot_connector, path: "/Users/dragosdaian/Documents/appsinacup/libgodot/samples/elixir_sample"}
	]
end
```

3. Run:

```bash
mix deps.get
mix compile
```

This uses the exact same compilation/precompile logic that Hex would.

### Test the precompiled download flow locally

You can simulate GitHub Releases by hosting the precompiled tarballs over HTTP locally.

1. In `samples/elixir_sample/`, build a precompiled archive for your current machine:

```bash
cd samples/elixir_sample
mix deps.get
mix elixir_make.precompile
```

The task prints the path of the generated archive (under your elixir_make cache dir).

2. Serve the directory containing that archive:

```bash
cd <the-folder-with-the-generated-.tar.gz>
python3 -m http.server 8080
```

3. In your scratch project, point the URL template to that server and compile:

```bash
export LIBGODOT_PRECOMPILED_URL='http://localhost:8080/@{artefact_filename}'
mix deps.clean --all
mix deps.get
mix compile
```

If everything matches, `mix compile` will download instead of building.

## Publishing precompiled artefacts (Hex + GitHub Releases)

To publish this to Hex in a way that "just works" for users:

1. Ensure `mix.exs` version (and release tag) match (e.g. `v4.5.1`).
2. Build per-target/per-OTP (NIF version) tarballs on CI using `mix elixir_make.precompile`.
3. Upload the `.tar.gz` artefacts and their checksum sidecar files (e.g. `.sha256`) to GitHub Releases.
4. Generate and commit `checksum-lib_godot_connector.exs` so Hex installs can verify downloads:

```bash
mix elixir_make.checksum --all
```

5. Make sure the checksum file is included in the Hex package (this project already includes it when present).

Note: artefacts are keyed by **target triple** and **Erlang NIF version**. If you want to support multiple OTP versions,
you need to publish artefacts for each of those NIF versions.

3.  Alternatively, build the NIF with CMake directly:

```bash
cd samples/elixir_sample
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

For a debug build:

```bash
cd samples/elixir_sample
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

4.  Run the Elixir code:

```bash
mix compile
iex -S mix
```

To run it as a normal OTP application (starts `LibGodot.Driver` under supervision):

```bash
mix run --no-halt
```

## Example Usage

```elixir
# In IEx
LibGodot.subscribe(self())

{:ok, godot} =
	LibGodot.create([
		"godot",
		"--headless",
		"--quit"
	])

# If you want to be explicit about which libgodot to load:
# {:ok, godot} = LibGodot.create("../../build/libgodot.dylib", ["godot", "--headless"])  # macOS
# {:ok, godot} = LibGodot.create("../../build/libgodot.so", ["godot", "--headless"])     # Linux

LibGodot.start(godot)

# Run a few frames (or drive this from a GenServer timer)
LibGodot.iteration(godot)
LibGodot.iteration(godot)

LibGodot.shutdown(godot)

# Wait for message
flush()
# Should see: {:godot_status, :started}
```

## Driving `iteration/1` from Elixir

For convenience, this sample includes a tiny GenServer that owns the Godot instance
and calls `iteration/1` on a timer:

```elixir
iex -S mix

{:ok, _pid} =
	LibGodot.Driver.start_link(
		interval_ms: 16,
		notify_pid: self()
	)

# You should see messages like:
# {:godot_status, :started}
flush()

# Send a message into Godot (available via Engine.get_singleton("ElixirBus") in scripts)
:ok = LibGodot.Driver.send_message("hello from Elixir")

# Request/reply: sends a request into Godot and blocks waiting for a response.
# Godot must call ElixirBus.respond(request_id, response) for this to complete.
{:ok, resp} = LibGodot.Driver.request("ping", 1_000)
IO.inspect(resp)

# Receive events sent from Godot via ElixirBus.send_event/2
LibGodot.subscribe(self())
flush()
```

On macOS, embedding Godot inside the BEAM is only supported in headless mode.
The driver defaults to `--headless` and the native layer disables AppKit initialization when it detects `--headless`.
You can override by passing `args: [...]`, but windowed mode may crash due to AppKit main-thread requirements.

Note: the sample project lives at `samples/project/`, so from `samples/elixir_sample/` the path is `../project/`.
