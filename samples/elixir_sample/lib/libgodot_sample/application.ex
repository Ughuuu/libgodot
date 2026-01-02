defmodule LibGodotSample.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      %{
        id: LibGodotSample.Godot,
        start: {LibGodot.Driver, :start_link, [[name: LibGodotSample.Godot, interval_ms: 16]]},
        restart: :transient
      },
      %{
        id: LibGodotSample.EventReceiver,
        start: {LibGodotSample.EventReceiver, :start_link, [[name: LibGodotSample.EventReceiver]]},
        restart: :permanent
      },
      %{
        id: LibGodotSample.Pinger,
        start: {LibGodotSample.Pinger, :start_link, [[name: LibGodotSample.Pinger, server: LibGodotSample.Godot, interval_ms: 1_000]]},
        restart: :permanent
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: LibGodotSample.Supervisor)
  end
end
