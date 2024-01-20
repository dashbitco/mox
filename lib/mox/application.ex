defmodule Mox.Application do
  @moduledoc false

  use Application

  def start(_, _) do
    children = [
      %{id: Mox, type: :worker, start: {Mox, :start_link_ownership, []}}
    ]

    Supervisor.start_link(children, name: Mox.Supervisor, strategy: :one_for_one)
  end
end
