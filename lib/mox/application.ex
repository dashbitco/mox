defmodule Mox.Application do
  @moduledoc false

  use Application

  def start(_, _) do
    children = [{Registry, name: Mox, keys: :unique}]
    Supervisor.start_link(children, name: Mox.Supervisor, strategy: :one_for_one)
  end
end