defmodule MoxTest.ClusterTest do
  use ExUnit.Case, async: true
  import Mox

  setup_all do
    Task.start_link(fn ->
      System.cmd("epmd", [])
    end)

    Process.sleep(100)
    {:ok, _} = :net_kernel.start([:primary, :shortnames])
    :peer.start(%{name: :peer})
    [peer] = Node.list()
    :rpc.call(peer, :code, :add_paths, [:code.get_path()])
    :rpc.call(peer, Application, :ensure_all_started, [:mix])
    :rpc.call(peer, Application, :ensure_all_started, [:logger])
    :rpc.call(peer, Logger, :configure, [[level: Logger.level()]])
    :rpc.call(peer, Mix, :env, [Mix.env()])
    :rpc.call(peer, Application, :ensure_all_started, [:mox])
    :ok
  end

  test "an allowance can commute over the cluster" do
    set_mox_private()

    Mox.expect(CalcMock, :add, &Kernel.+/2)

    quoted =
      quote do
        primary =
          receive do
            {:unblock, pid} -> pid
          end

        send(primary, {:result, CalcMock.add(1, 1)})
      end

    peer =
      Node.list()
      |> List.first()
      |> Node.spawn(Code, :eval_quoted, [quoted])

    Mox.allow(CalcMock, self(), peer)
    send(peer, {:unblock, self()})
    assert_receive {:result, 2}
  end
end
