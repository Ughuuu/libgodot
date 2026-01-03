defmodule LibGodot.Port do
  @moduledoc """
  Port-based implementation of LibGodot that runs Godot in a separate process.
  This avoids threading/mutex issues by running Godot on its own main thread.
  """
  
  use GenServer
  
  defstruct [:port, :ref, :subscriber, :pending_requests]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  def create(args) do
    GenServer.call(__MODULE__, {:create, args, nil})
  end
  
  def create(lib_path, args) do
    GenServer.call(__MODULE__, {:create, args, lib_path})
  end
  
  def start(ref) do
    GenServer.call(__MODULE__, {:start, ref})
  end
  
  def iteration(ref) do
    GenServer.call(__MODULE__, {:iteration, ref})
  end
  
  def shutdown(ref) do
    GenServer.call(__MODULE__, {:shutdown, ref})
  end
  
  def send_message(ref, msg) do
    GenServer.call(__MODULE__, {:send_message, ref, msg})
  end
  
  def subscribe(pid) do
    GenServer.call(__MODULE__, {:subscribe, pid})
  end
  
  @impl true
  def init(_opts) do
    port_path = find_port_executable()
    port = Port.open({:spawn_executable, port_path}, [
      {:args, []},
      :binary,
      :use_stdio,
      :exit_status
    ])
    
    {:ok, %__MODULE__{port: port, ref: nil, subscriber: nil, pending_requests: %{}}}
  end
  
  @impl true
  def handle_call({:create, args, lib_path}, _from, state) do
    cmd = if lib_path do
      Jason.encode!(%{cmd: "create", args: args, lib_path: lib_path})
    else
      Jason.encode!(%{cmd: "create", args: args})
    end
    
    send(state.port, {self(), {:command, cmd <> "\n"}})
    
    response = wait_for_response(state.port)
    
    case response do
      {:ok, %{"ok" => true, "ref" => ref}} ->
        {:reply, {:ok, ref}, %{state | ref: ref}}
      {:ok, %{"ok" => false, "error" => error}} ->
        {:reply, {:error, error}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:start, ref}, _from, state) do
    cmd = Jason.encode!(%{cmd: "start", ref: ref})
    send(state.port, {self(), {:command, cmd <> "\n"}})
    
    response = wait_for_response(state.port)
    
    case response do
      {:ok, %{"ok" => true}} ->
        {:reply, :ok, state}
      {:ok, %{"ok" => false, "error" => error}} ->
        {:reply, {:error, error}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:iteration, ref}, _from, state) do
    cmd = Jason.encode!(%{cmd: "iteration", ref: ref})
    send(state.port, {self(), {:command, cmd <> "\n"}})
    
    response = wait_for_response(state.port)
    
    case response do
      {:ok, %{"ok" => true, "quit" => true}} ->
        {:reply, {:error, "quit"}, state}
      {:ok, %{"ok" => true, "quit" => false}} ->
        {:reply, :ok, state}
      {:ok, %{"ok" => false, "error" => error}} ->
        {:reply, {:error, error}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:shutdown, ref}, _from, state) do
    cmd = Jason.encode!(%{cmd: "shutdown", ref: ref})
    send(state.port, {self(), {:command, cmd <> "\n"}})
    
    response = wait_for_response(state.port)
    
    case response do
      {:ok, %{"ok" => true}} ->
        {:reply, :ok, %{state | ref: nil}}
      {:ok, %{"ok" => false, "error" => error}} ->
        {:reply, {:error, error}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:request, ref, msg, timeout_ms}, {_from_pid, _ref} = from, state) do
    # Generate unique request ID
    request_id = :erlang.unique_integer([:positive])

    # Send request to Godot with ID
    cmd = Jason.encode!(%{cmd: "request", ref: ref, msg: msg, request_id: request_id})
    send(state.port, {self(), {:command, cmd <> "\n"}})

    # Wait for command acknowledgment
    case wait_for_response(state.port) do
      {:ok, %{"ok" => true}} ->
        # Store pending request
        timer_ref = Process.send_after(self(), {:request_timeout, request_id}, timeout_ms)
        pending_requests = Map.put(state.pending_requests, request_id, %{from: from, timer: timer_ref})

        {:noreply, %{state | pending_requests: pending_requests}}
      {:ok, %{"ok" => false, "error" => error}} ->
        {:reply, {:error, error}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:send_message, ref, msg}, _from, state) do
    cmd = Jason.encode!(%{cmd: "send_message", ref: ref, msg: msg})
    send(state.port, {self(), {:command, cmd <> "\n"}})

    response = wait_for_response(state.port)

    case response do
      {:ok, %{"ok" => true}} ->
        {:reply, :ok, state}
      {:ok, %{"ok" => false, "error" => error}} ->
        {:reply, {:error, error}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscriber: pid}}
  end
  
  @impl true
  def handle_info({port, {:data, data}}, %{port: port, subscriber: subscriber, pending_requests: pending_requests} = state) do
    case Jason.decode(data) do
      {:ok, %{"response" => request_id, "data" => response_data}} ->
        # Handle request response from Godot
        case Map.get(pending_requests, request_id) do
          %{from: from, timer: timer_ref} ->
            # Cancel timeout timer
            Process.cancel_timer(timer_ref)
            # Reply to waiting process
            GenServer.reply(from, {:ok, response_data})
            # Remove from pending requests
            pending_requests = Map.delete(pending_requests, request_id)
            {:noreply, %{state | pending_requests: pending_requests}}
          nil ->
            # Response for unknown request - ignore
            {:noreply, state}
        end
      {:ok, %{"event" => "message", "data" => msg}} when not is_nil(subscriber) ->
        # Handle event messages from Godot
        send(subscriber, {:godot_message, msg})
        {:noreply, state}
      _ ->
        # Skip other messages (command responses are handled in handle_call)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:request_timeout, request_id}, %{pending_requests: pending_requests} = state) do
    # Handle request timeout
    case Map.get(pending_requests, request_id) do
      %{from: from} ->
        # Reply with timeout error
        GenServer.reply(from, {:error, :timeout})
        # Remove from pending requests
        pending_requests = Map.delete(pending_requests, request_id)
        {:noreply, %{state | pending_requests: pending_requests}}
      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    {:stop, {:port_exit, status}, state}
  end

  # Wait for a command response (not an event)
  defp wait_for_response(port) do
    receive do
      {^port, {:data, {:eol, data}}} ->
        # Handle line-based data (stdout)
        case Jason.decode(data) do
          {:ok, json} when is_map(json) ->
            # Check if it's a command response (has "ok" key) or an event
            if Map.has_key?(json, "ok") do
              {:ok, json}
            else
              # It's an event, wait for the next message
              wait_for_response(port)
            end
          {:error, _error} ->
            # Not JSON - might be stderr or other output, skip it
            wait_for_response(port)
        end
      {^port, {:data, data}} when is_binary(data) ->
        # Handle binary data
        case Jason.decode(data) do
          {:ok, json} when is_map(json) ->
            if Map.has_key?(json, "ok") do
              {:ok, json}
            else
              wait_for_response(port)
            end
          {:error, _} ->
            # Not JSON - might be stderr or other output, skip it
            wait_for_response(port)
        end
    after
      5000 ->
        {:error, "timeout"}
    end
  end

  defp find_port_executable do
    candidates = [
      Application.app_dir(:lib_godot_connector, "priv/libgodot_port"),
      Path.join([File.cwd!(), "priv", "libgodot_port"])
    ]
    
    Enum.find(candidates, &File.exists?/1) || 
      raise "libgodot_port executable not found in #{inspect(candidates)}"
  end
end

