defmodule Mox.Server do
  @moduledoc false

  use GenServer
  @timeout 30000
  @this {:global, __MODULE__}

  # API

  def child_spec(_options) do
    %{id: __MODULE__, start: {__MODULE__, :start_ownership_server_link, []}}
  end

  def start_ownership_server_link do
    case NimbleOwnership.start_link(name: @this) do
      {:error, {:already_started, _}} -> :ignore
      other -> other
    end
  end

  def add_expectation(owner_pid, {mock, _, _} = key, expectation) do
    case NimbleOwnership.fetch_owner(@this, [owner_pid], mock) do
      {:ok, ^owner_pid} ->
        :ok

      {:ok, other_owner} ->
        throw({:error, {:currently_allowed, other_owner}})

      :error ->
        :ok
    end

    {:ok, :ok} =
      NimbleOwnership.get_and_update(@this, owner_pid, mock, fn
        nil ->
          {:ok, %{key => expectation}}

        %{} = expectations ->
          {:ok, Map.update(expectations, key, expectation, &merge_expectation(&1, expectation))}
      end)

    :ok
  catch
    return -> return
  end

  def fetch_fun_to_dispatch(caller_pids, {mock, _, _} = key) do
    owner_pid =
      case NimbleOwnership.fetch_owner(@this, caller_pids, mock) do
        {:ok, owner_pid} -> owner_pid
        :error -> throw(:no_expectation)
      end

    {:ok, return} =
      NimbleOwnership.get_and_update(@this, owner_pid, mock, fn expectations ->
        case expectations[key] do
          nil ->
            {:no_expectation, expectations}

          {total, [], nil} ->
            {{:out_of_expectations, total}, expectations}

          {_, [], stub} ->
            {{ok_or_remote(self()), stub}, expectations}

          {total, [call | calls], stub} ->
            new_expectations = put_in(expectations[key], {total, calls, stub})
            {{ok_or_remote(self()), call}, new_expectations}
        end
      end)

    return
  catch
    return -> return
  end

  def verify(owner_pid, for, test_or_on_exit) do
    expectations = NimbleOwnership.get_owned(@this, owner_pid, %{})

    pending =
      for {_mock, expected_funs} <- expectations,
          {{module, _, _} = key, {count, [_ | _] = calls, _stub}} <- expected_funs,
          module == for or for == :all do
        {key, count, length(calls)}
      end

    # state =
    #   if test_or_on_exit == :on_exit do
    #     down(state, owner_pid)
    #   else
    #     state
    #   end

    pending
  end

  def verify_on_exit(pid) do
    # raise "TODO"
    :ok
    # GenServer.call(@this, {:verify_on_exit, pid}, @timeout)
  end

  def allow(mock, owner_pid, pid_or_function) do
    NimbleOwnership.allow(@this, owner_pid, pid_or_function, mock)
  end

  def set_mode(_owner_pid, :private), do: NimbleOwnership.set_mode_to_private(@this)
  def set_mode(owner_pid, :global), do: NimbleOwnership.set_mode_to_global(@this, owner_pid)

  # Callbacks

  # def handle_call(msg, _from, state) do
  #   # The global process may have terminated and we did not receive
  #   # the DOWN message yet, so we always check accordingly if it is alive.
  #   with %{mode: :global, global_owner_pid: global_owner_pid} <- state,
  #        false <- Process.alive?(global_owner_pid) do
  #     handle_call(msg, reset_global_mode(state))
  #   else
  #     _ -> handle_call(msg, state)
  #   end
  # end

  # Helper functions

  defp reset_global_mode(state) do
    %{state | mode: :private, global_owner_pid: nil}
  end

  defp down(state, pid) do
    {_, state} = pop_in(state.expectations[pid])
    state
  end

  defp maybe_add_and_monitor_pid(state, pid) do
    maybe_add_and_monitor_pid(state, pid, :DOWN, & &1)
  end

  defp maybe_add_and_monitor_pid(state, pid, on, fun) do
    case state.deps do
      %{^pid => entry} ->
        put_in(state.deps[pid], fun.(entry))

      _ ->
        Process.monitor(pid)
        state = put_in(state.deps[pid], {on, []})
        state
    end
  end

  defp merge_expectation({current_n, current_calls, _current_stub}, {n, calls, stub}) do
    {current_n + n, current_calls ++ calls, stub}
  end

  defp ok_or_remote(source) when node(source) == node(), do: :ok
  defp ok_or_remote(_source), do: :remote
end
