defmodule MoxTest.ClusterTest do
  use ExUnit.Case
  import Mox

  setup_all do
    Task.start_link(fn ->
      System.cmd("epmd", [])
    end)

    {:ok, _} = :net_kernel.start([:primary, :shortnames])
    :peer.start(%{name: :peer})
    [peer] = Node.list()
    :rpc.call(peer, :code, :add_paths, [:code.get_path()])
    :rpc.call(peer, Application, :ensure_all_started, [:mix])
    :rpc.call(peer, Application, :ensure_all_started, [:logger])
    :rpc.call(peer, Logger, :configure, [[level: Logger.level()]])
    :rpc.call(peer, Mix, :env, [Mix.env()])
    # force the primary global Mox Server registration to be synced, otherwise
    # there is a race condition, since global doesn't actively sync all the time.
    # the sync event should happen BEFORE connecting mox, otherwise it is not
    # deterministic which global mox server will survive.
    :rpc.call(peer, :global, :sync, [])
    :rpc.call(peer, Application, :ensure_all_started, [:mox])
    :ok
  end

  test "an allowance can commute over the cluster in private mode" do
    set_mox_private()

    Mox.expect(CalcMock, :add, fn a, b -> a + b end)

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

  test "an allowance can commute over the cluster in global mode" do
    set_mox_global()

    Mox.expect(CalcMock, :add, fn a, b -> a + b end)

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

    send(peer, {:unblock, self()})
    assert_receive {:result, 2}
  end
end
